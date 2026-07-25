"""Worker adapter inventory catalog.

Talking to Hermes or Jaeger is not just "CLI vs MCP." Each framework is a
host for:

  * multiple **models** (local and/or cloud)
  * multiple **transports** (CLI, HTTP gateway, MCP, reverse APIs, …)
  * optional **MCP servers / tools** (declared even when ARES is not using them)
  * optional **gateways** (ARES jros gateway, hermes-webui, etc.)

Latency and quality depend heavily on the **active model/provider config**
inside that framework, not only on which socket ARES opens.

Adapters must **catalog** what they can expose so System / Companion / SI
routing can reason about the world. Catalog entries may be ``in_use=False`` —
discovery is not the same as the currently selected execution path.
"""

from __future__ import annotations

from typing import Any, Iterable


def model_entry(
    *,
    id: str,
    label: str | None = None,
    location: str,
    provider: str | None = None,
    in_use: bool = False,
    source: str | None = None,
    notes: str | None = None,
) -> dict[str, Any]:
    """location: ``local`` | ``cloud`` | ``unknown``."""
    loc = str(location or "unknown").strip().lower()
    if loc not in {"local", "cloud", "unknown"}:
        loc = "unknown"
    return {
        "id": id,
        "label": label or id,
        "location": loc,
        "provider": provider,
        "in_use": bool(in_use),
        "source": source,
        "notes": notes,
    }


def transport_entry(
    *,
    id: str,
    kind: str,
    label: str | None = None,
    in_use: bool = False,
    endpoint: str | None = None,
    notes: str | None = None,
) -> dict[str, Any]:
    """kind: ``cli`` | ``http_gateway`` | ``mcp`` | ``subprocess`` | ``other``."""
    return {
        "id": id,
        "kind": kind,
        "label": label or id,
        "in_use": bool(in_use),
        "endpoint": endpoint,
        "notes": notes,
    }


def gateway_entry(
    *,
    id: str,
    kind: str,
    label: str | None = None,
    endpoint: str | None = None,
    in_use: bool = False,
    protocol: str | None = None,
    notes: str | None = None,
) -> dict[str, Any]:
    return {
        "id": id,
        "kind": kind,
        "label": label or id,
        "endpoint": endpoint,
        "in_use": bool(in_use),
        "protocol": protocol,
        "notes": notes,
    }


def mcp_entry(
    *,
    id: str,
    label: str | None = None,
    command: str | None = None,
    args: Iterable[str] | None = None,
    in_use_by_ares: bool = False,
    used_by: list[str] | None = None,
    notes: str | None = None,
) -> dict[str, Any]:
    return {
        "id": id,
        "label": label or id,
        "command": command,
        "args": list(args or []),
        "in_use_by_ares": bool(in_use_by_ares),
        "used_by": list(used_by or []),
        "notes": notes,
    }


def empty_inventory(*, worker_id: str, display_name: str) -> dict[str, Any]:
    return {
        "worker_id": worker_id,
        "display_name": display_name,
        "schema_version": 1,
        "models": [],
        "providers": [],
        "transports": [],
        "gateways": [],
        "mcp": [],
        "tools_summary": [],
        "latency": {
            "depends_on": [
                "selected_model",
                "provider_location",
                "transport",
                "tool_use",
                "cold_start",
            ],
            "note": (
                "Wall-clock time is dominated by the active LLM configuration "
                "inside the worker (local vs cloud model, load, tools), not "
                "only by the ARES transport used to reach the worker."
            ),
        },
        "active_execution": None,
    }


def finalize_inventory(payload: dict[str, Any]) -> dict[str, Any]:
    base = empty_inventory(
        worker_id=str(payload.get("worker_id") or "unknown"),
        display_name=str(payload.get("display_name") or payload.get("worker_id") or "Worker"),
    )
    for key in ("models", "providers", "transports", "gateways", "mcp", "tools_summary"):
        if isinstance(payload.get(key), list):
            base[key] = payload[key]
    if isinstance(payload.get("latency"), dict):
        base["latency"] = {**base["latency"], **payload["latency"]}
    if payload.get("active_execution") is not None:
        base["active_execution"] = payload["active_execution"]
    if payload.get("notes"):
        base["notes"] = payload["notes"]
    if isinstance(payload.get("default"), dict):
        base["default"] = payload["default"]
    return base


def infer_model_location(provider: str | None, model_id: str | None = None) -> str:
    """Best-effort local/cloud classification from provider/model strings."""
    p = str(provider or "").strip().lower()
    m = str(model_id or "").strip().lower()
    local_markers = (
        "local", "ollama", "mlx", "llama.cpp", "llamacpp", "gguf",
        "lmstudio", "vllm", "onnx", "metal", "cuda",
    )
    cloud_markers = (
        "cloud", "openai", "anthropic", "google", "gemini", "xai", "grok",
        "openrouter", "deepseek", "together", "fireworks", "azure", "bedrock",
        "mistral", "cohere", "ollama-cloud",
    )
    blob = f"{p} {m}"
    if any(k in blob for k in cloud_markers) and "ollama-cloud" in blob:
        return "cloud"
    if any(k in p for k in cloud_markers) or any(k in m for k in ("gpt-", "claude", "gemini-", "grok-")):
        if "local" in p or p in {"ollama", "mlx"}:
            return "local"
        if any(k in p for k in cloud_markers):
            return "cloud"
    if any(k in p for k in local_markers) or m.endswith(".gguf") or ":latest" in m:
        return "local"
    if any(k in p for k in cloud_markers):
        return "cloud"
    return "unknown"
