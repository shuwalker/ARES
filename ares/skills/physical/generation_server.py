"""ARES 3D Generation MCP Server — ComfyUI 3D model generation (Meshy, Tripo, Rodin, Hunyuan3D).

Tools:
- generate_3d_from_image : Convert image → 3D model via ComfyUI
- generate_3d_from_text  : Convert text → 3D model via ComfyUI
- check_generation_status: Poll ComfyUI for job completion
- list_comfyui_3d_nodes   : List installed 3D generation nodes
- generate_avatar_variant : High-level ARES avatar generation
- comfyui_health          : Check ComfyUI liveness

MCP :9517, StreamableHTTP.
"""

from __future__ import annotations

import asyncio
import logging
import os
import time
import uuid
from pathlib import Path
from typing import Any, Optional

import httpx
from mcp.server.fastmcp import FastMCP

logger = logging.getLogger("ares.generation")

COMFY_HOST = os.environ.get("COMFYUI_HOST", "127.0.0.1")
COMFY_PORT = int(os.environ.get("COMFYUI_PORT", "8188"))
COMFY_URL = f"http://{COMFY_HOST}:{COMFY_PORT}"
RESULT_DIR = Path("/tmp/ares_generation")
RESULT_DIR.mkdir(parents=True, exist_ok=True)

server = FastMCP(
    name="ARES Generation",
    instructions="3D generation tools powered by ComfyUI. Supports Meshy, Tripo, Rodin, and Hunyuan3D for image-to-3D, text-to-3D, and avatar variants.",
    host="0.0.0.0",
    port=9517,
)

# ═══ Lazy ComfyUI client singleton ═══════════════════════════════════════════

_comfy_client: Optional[httpx.AsyncClient] = None
_comfy_available: Optional[bool] = None


def _get_comfy_client() -> httpx.AsyncClient:
    global _comfy_client
    if _comfy_client is None:
        _comfy_client = httpx.AsyncClient(timeout=httpx.Timeout(30.0, connect=5.0))
    return _comfy_client


async def _check_comfyui() -> bool:
    global _comfy_available
    if _comfy_available is not None:
        return _comfy_available
    client = _get_comfy_client()
    try:
        r = await client.get(f"{COMFY_URL}/system_stats", timeout=5.0)
        _comfy_available = r.status_code == 200
    except Exception:
        _comfy_available = False
    return _comfy_available


def _graceful_error(message: str) -> dict:
    return {"status": "error", "error": message}


# ═══ ComfyUI node identifiers (common custom-node class names) ════════════════

_PROVIDER_NODES: dict[str, dict[str, str]] = {
    "meshy": {
        "text_to_3d": "MeshyTextTo3D",
        "image_to_3d": "MeshyImageTo3D",
    },
    "tripo": {
        "text_to_3d": "TripoAPIDraft Node",
        "image_to_3d": "TripoAPIDraft Node",
    },
    "rodin": {
        "text_to_3d": "RodinTextTo3D",
        "image_to_3d": "RodinImageTo3D",
    },
    "hunyuan": {
        "text_to_3d": "HunyuanDiTNode",
        "image_to_3d": "Hunyuan3DNode",
    },
}

_AVATAR_STYLE_CONCEPTS: dict[str, str] = {
    "synthMuse": "a futuristic luminous humanoid musician with flowing neon hair, cyberpunk aesthetic, chrome and glass materials",
    "warriorSage": "an ancient armored warrior monk with glowing runes, metallic robes, wise and battle-worn, fantasy 3D character",
    "ballCompanion": "a cute spherical floating robot companion, smooth glossy surface, LED eyes, friendly sci-fi drone",
    "mysticVoid": "an ethereal shadow creature from the void, translucent smoke body, glowing purple eyes, dark fantasy 3D model",
}


def _build_text_to_3d_workflow(description: str, provider: str) -> dict[str, Any]:
    """Build a minimal ComfyUI prompt JSON for text-to-3D."""
    node_class = _PROVIDER_NODES.get(provider, _PROVIDER_NODES["meshy"])["text_to_3d"]
    workflow: dict[str, Any] = {
        "1": {
            "class_type": node_class,
            "inputs": {
                "prompt": description,
                "negative_prompt": "low quality, blurry, distorted",
            },
        },
        "2": {
            "class_type": "SaveGLB",
            "inputs": {
                "model": ["1", 0],
                "filename_prefix": f"ares_text_{provider}",
            },
        },
    }
    return workflow


def _build_image_to_3d_workflow(image_path: str, provider: str, style: str) -> dict[str, Any]:
    """Build a minimal ComfyUI prompt JSON for image-to-3D."""
    node_class = _PROVIDER_NODES.get(provider, _PROVIDER_NODES["meshy"])["image_to_3d"]
    workflow: dict[str, Any] = {
        "1": {
            "class_type": "LoadImage",
            "inputs": {"image": image_path},
        },
        "2": {
            "class_type": node_class,
            "inputs": {
                "image": ["1", 0],
                "style": style,
            },
        },
        "3": {
            "class_type": "SaveGLB",
            "inputs": {
                "model": ["2", 0],
                "filename_prefix": f"ares_image_{provider}",
            },
        },
    }
    return workflow


async def _queue_prompt(workflow: dict[str, Any]) -> dict:
    """Queue a ComfyUI prompt and return the response."""
    client = _get_comfy_client()
    payload = {
        "prompt": workflow,
        "client_id": str(uuid.uuid4()),
    }
    r = await client.post(f"{COMFY_URL}/prompt", json=payload)
    r.raise_for_status()
    return r.json()


async def _fetch_history(prompt_id: str) -> Optional[dict]:
    """Fetch ComfyUI history for a prompt ID."""
    client = _get_comfy_client()
    try:
        r = await client.get(f"{COMFY_URL}/history/{prompt_id}", timeout=10.0)
        if r.status_code == 200:
            return r.json()
    except Exception as e:
        logger.debug("History fetch failed for %s: %s", prompt_id, e)
    return None


def _find_output_path(history: dict, prompt_id: str) -> Optional[str]:
    """Extract saved output file path from ComfyUI history."""
    entry = history.get(prompt_id, history) if isinstance(history, dict) else history
    if not isinstance(entry, dict):
        return None
    outputs = entry.get("outputs", {})
    for node_id, node_out in outputs.items():
        if isinstance(node_out, dict):
            for key in ("gltf", "glb", "mesh", "images", "files"):
                files = node_out.get(key, [])
                if isinstance(files, list) and files:
                    f = files[0]
                    if isinstance(f, str):
                        return f
                    if isinstance(f, dict):
                        return f.get("filename") or f.get("name")
                elif isinstance(files, dict):
                    for sub in files.values():
                        if isinstance(sub, list) and sub:
                            first = sub[0]
                            return first if isinstance(first, str) else first.get("filename")
    return None


def _guess_output_file_path(filename_hint: Optional[str]) -> Optional[str]:
    """Guess absolute path from ComfyUI output hint."""
    if not filename_hint:
        return None
    output_dir = Path.home() / "ComfyUI" / "output"
    # Also check common ComfyUI paths
    candidates = [
        output_dir / filename_hint,
        RESULT_DIR / filename_hint,
        Path("/ComfyUI/output") / filename_hint,
        Path(os.getcwd()) / "output" / filename_hint,
    ]
    for p in candidates:
        if p.exists():
            return str(p.resolve())
    # Return the best guess even if not yet on disk
    return str(RESULT_DIR / filename_hint)


async def _poll_until_complete(prompt_id: str, max_wait: float = 300.0, interval: float = 2.0) -> dict:
    """Poll ComfyUI for prompt completion. Returns status dict."""
    start = time.time()
    last_status = "pending"
    result_path: Optional[str] = None

    while time.time() - start < max_wait:
        history = await _fetch_history(prompt_id)
        if history is not None:
            entry = history.get(prompt_id, history) if isinstance(history, dict) else history
            if isinstance(entry, dict):
                status = entry.get("status", {})
                exec_info = status.get("status_str", "").lower() if isinstance(status, dict) else ""
                if exec_info in ("completed", "success") or entry.get("outputs"):
                    last_status = "complete"
                    filename_hint = _find_output_path(history, prompt_id)
                    result_path = _guess_output_file_path(filename_hint)
                    break
                elif exec_info in ("error", "failed"):
                    last_status = "failed"
                    break

        # Fallback: check /queue endpoint
        try:
            client = _get_comfy_client()
            r = await client.get(f"{COMFY_URL}/queue", timeout=5.0)
            if r.status_code == 200:
                q = r.json()
                running = q.get("queue_running", [])
                pending = q.get("queue_pending", [])
                if not any(pid == prompt_id for pid in running + pending):
                    # Not in queue → assume finished; double-check history
                    pass
        except Exception:
            pass

        await asyncio.sleep(interval)

    file_size = None
    if result_path and os.path.exists(result_path):
        file_size = os.path.getsize(result_path)

    return {
        "status": last_status,
        "prompt_id": prompt_id,
        "result_path": result_path,
        "file_size_bytes": file_size,
    }


# ═══ Tools ══════════════════════════════════════════════════════════════════


@server.tool()
async def generate_3d_from_image(image_path: str, provider: str = "meshy", style: str = "realistic") -> dict:
    """Send an image to ComfyUI for 3D model generation.

    Args:
        image_path: Absolute or ~-expanded path to the source image.
        provider: One of "meshy", "tripo", "rodin", "hunyuan".
        style: Visual style hint (e.g. "realistic", "cartoon", "anime").

    Returns:
        dict: status, prompt_id, result_path (when complete).
    """
    if not await _check_comfyui():
        return _graceful_error("ComfyUI is not running or unreachable at " + COMFY_URL)

    p = Path(image_path).expanduser().resolve()
    if not p.exists():
        return _graceful_error(f"Image not found: {image_path}")

    provider = provider.lower()
    if provider not in _PROVIDER_NODES:
        return _graceful_error(f"Unknown provider '{provider}'. Choose from: {', '.join(_PROVIDER_NODES.keys())}")

    # Upload image to ComfyUI so it can be referenced in workflow
    client = _get_comfy_client()
    uploaded_name: Optional[str] = None
    try:
        with open(p, "rb") as f:
            r = await client.post(
                f"{COMFY_URL}/upload/image",
                files={"image": (p.name, f, "image/png")},
                data={"type": "input", "overwrite": "true"},
                timeout=30.0,
            )
        if r.status_code == 200:
            data = r.json()
            uploaded_name = data.get("name") or p.name
        else:
            logger.warning("Image upload returned %s, falling back to local path", r.status_code)
            uploaded_name = str(p)
    except Exception as e:
        logger.error("Image upload failed: %s", e)
        uploaded_name = str(p)

    workflow = _build_image_to_3d_workflow(uploaded_name or str(p), provider, style)
    try:
        resp = await _queue_prompt(workflow)
    except Exception as e:
        return _graceful_error(f"Failed to queue prompt: {e}")

    prompt_id = resp.get("prompt_id")
    if not prompt_id:
        return _graceful_error("ComfyUI did not return a prompt_id")

    # Brief async poll (non-blocking for the tool call itself)
    poll = await _poll_until_complete(prompt_id, max_wait=60.0, interval=2.0)
    return {
        "status": "queued" if poll["status"] == "pending" else poll["status"],
        "prompt_id": prompt_id,
        "result_path": poll.get("result_path"),
        "comfy_url": COMFY_URL,
    }


@server.tool()
async def generate_3d_from_text(description: str, provider: str = "meshy") -> dict:
    """Generate a 3D model from a text description via ComfyUI.

    Args:
        description: Text prompt describing the desired 3D model.
        provider: One of "meshy", "tripo", "rodin", "hunyuan".

    Returns:
        dict: status, prompt_id, result_path (when complete).
    """
    if not await _check_comfyui():
        return _graceful_error("ComfyUI is not running or unreachable at " + COMFY_URL)

    provider = provider.lower()
    if provider not in _PROVIDER_NODES:
        return _graceful_error(f"Unknown provider '{provider}'. Choose from: {', '.join(_PROVIDER_NODES.keys())}")

    workflow = _build_text_to_3d_workflow(description, provider)
    try:
        resp = await _queue_prompt(workflow)
    except Exception as e:
        return _graceful_error(f"Failed to queue prompt: {e}")

    prompt_id = resp.get("prompt_id")
    if not prompt_id:
        return _graceful_error("ComfyUI did not return a prompt_id")

    poll = await _poll_until_complete(prompt_id, max_wait=60.0, interval=2.0)
    return {
        "status": "queued" if poll["status"] == "pending" else poll["status"],
        "prompt_id": prompt_id,
        "result_path": poll.get("result_path"),
        "comfy_url": COMFY_URL,
    }


@server.tool()
async def check_generation_status(prompt_id: str) -> dict:
    """Check if a ComfyUI 3D generation job is complete.

    Args:
        prompt_id: The prompt_id returned by generate_3d_from_image or generate_3d_from_text.

    Returns:
        dict: status (pending/complete/failed), result_path, file_size_bytes.
    """
    if not await _check_comfyui():
        return _graceful_error("ComfyUI is not running or unreachable at " + COMFY_URL)

    history = await _fetch_history(prompt_id)
    if history is None:
        return _graceful_error(f"No history found for prompt_id: {prompt_id}")

    entry = history.get(prompt_id, history) if isinstance(history, dict) else history
    if not isinstance(entry, dict):
        return _graceful_error("Unexpected history format from ComfyUI")

    status = entry.get("status", {})
    exec_info = status.get("status_str", "").lower() if isinstance(status, dict) else ""
    if exec_info in ("completed", "success") or entry.get("outputs"):
        filename_hint = _find_output_path(history, prompt_id)
        result_path = _guess_output_file_path(filename_hint)
        file_size = os.path.getsize(result_path) if result_path and os.path.exists(result_path) else None
        return {
            "status": "complete",
            "result_path": result_path,
            "file_size_bytes": file_size,
        }
    elif exec_info in ("error", "failed"):
        return {"status": "failed", "error": entry.get("status", {}).get("error", "Unknown error")}

    return {"status": "pending", "result_path": None, "file_size_bytes": None}


@server.tool()
async def list_comfyui_3d_nodes() -> dict:
    """List available 3D generation nodes in the local ComfyUI installation.

    Returns:
        dict: nodes list and provider list.
    """
    if not await _check_comfyui():
        return _graceful_error("ComfyUI is not running or unreachable at " + COMFY_URL)

    client = _get_comfy_client()
    try:
        r = await client.get(f"{COMFY_URL}/object_info", timeout=10.0)
        r.raise_for_status()
        data = r.json()
    except Exception as e:
        return _graceful_error(f"Failed to fetch object_info: {e}")

    known_3d_nodes = set()
    for provider, nodes in _PROVIDER_NODES.items():
        known_3d_nodes.update(nodes.values())

    found = []
    for class_name in data:
        if class_name in known_3d_nodes or any(
            token in class_name.lower() for token in ("meshy", "tripo", "rodin", "hunyuan", "3d", "mesh", "glb", "gltf")
        ):
            found.append(class_name)

    providers = list(_PROVIDER_NODES.keys())
    return {"nodes": sorted(set(found)), "providers": providers}


@server.tool()
async def generate_avatar_variant(style: str = "synthMuse", description: str = "") -> dict:
    """High-level tool that generates an ARES avatar variant.

    Args:
        style: One of "synthMuse", "warriorSage", "ballCompanion", "mysticVoid".
        description: Optional extra description appended to the base concept.

    Returns:
        dict: status, prompt_id, result_path, generated_prompt.
    """
    if not await _check_comfyui():
        return _graceful_error("ComfyUI is not running or unreachable at " + COMFY_URL)

    style = style.lower()
    if style == "synthmuse":
        style = "synthMuse"
    elif style == "warriorsage":
        style = "warriorSage"
    elif style == "ballcompanion":
        style = "ballCompanion"
    elif style == "mysticvoid":
        style = "mysticVoid"

    if style not in _AVATAR_STYLE_CONCEPTS:
        return _graceful_error(f"Unknown style '{style}'. Choose from: {', '.join(_AVATAR_STYLE_CONCEPTS.keys())}")

    base_prompt = _AVATAR_STYLE_CONCEPTS[style]
    full_prompt = f"{base_prompt}. {description}" if description else base_prompt

    # Use Meshy as the default high-quality avatar provider
    provider = "meshy"
    workflow = _build_text_to_3d_workflow(full_prompt, provider)
    try:
        resp = await _queue_prompt(workflow)
    except Exception as e:
        return _graceful_error(f"Failed to queue avatar prompt: {e}")

    prompt_id = resp.get("prompt_id")
    if not prompt_id:
        return _graceful_error("ComfyUI did not return a prompt_id")

    poll = await _poll_until_complete(prompt_id, max_wait=120.0, interval=2.0)
    return {
        "status": "queued" if poll["status"] == "pending" else poll["status"],
        "prompt_id": prompt_id,
        "result_path": poll.get("result_path"),
        "generated_prompt": full_prompt,
        "style": style,
        "provider": provider,
    }


@server.tool()
async def comfyui_health() -> dict:
    """Check if ComfyUI is running and responsive.

    Returns:
        dict: running, version, models_loaded.
    """
    client = _get_comfy_client()
    try:
        r = await client.get(f"{COMFY_URL}/system_stats", timeout=5.0)
        if r.status_code != 200:
            return {"running": False, "version": None, "models_loaded": 0, "detail": r.text[:200]}
        data = r.json()
        return {
            "running": True,
            "version": data.get("system", {}).get("comfyui_version", "unknown"),
            "models_loaded": len(data.get("models", [])),
        }
    except Exception as e:
        return {"running": False, "version": None, "models_loaded": 0, "detail": str(e)}


# ═══ Entrypoint ═══════════════════════════════════════════════════════════════

if __name__ == "__main__":
    server.run(transport="streamable-http")
