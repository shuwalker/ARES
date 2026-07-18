"""ARES Hatchery — hardware scan, personality molding, and Ollama model hatching.

The Hatchery is ARES's onboarding flow for creating a local Synthetic Intelligence
companion. It:

1. Scans hardware (RAM, GPU, disk speed) to recommend the best local LLM.
2. Lets the user mold personality: system prompt, temperature, top_p, thinking mode.
3. Hatches: creates an Ollama Modelfile, runs `ollama create`, registers the
   hatched SI as a backend in ARES's router, and saves a birth certificate.

Each hatched SI is just an Ollama model with a custom system prompt and parameters —
a Modelfile. The Hatchery wraps `ollama create` in a ritual.
"""

from __future__ import annotations

import json
import logging
import os
import re
import shutil
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List

from api.backends.base import AgenticBackend
from api.backends.router import get_router

logger = logging.getLogger(__name__)

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://127.0.0.1:11434")
HATCHERY_DIR = Path(os.environ.get("ARES_HATCHERY_DIR", str(Path.home() / ".ares" / "hatchery")))

MODelfILE_TEMPLATE = """FROM {base_model}

SYSTEM \"\"\"{system_prompt}\"\"\"

PARAMETER temperature {temperature}
PARAMETER top_p {top_p}
PARAMETER num_ctx {num_ctx}
{think_line}"""


def scan_hardware() -> Dict[str, Any]:
    """Detect hardware specs and recommend the best local LLM."""
    import platform

    info: Dict[str, Any] = {
        "platform": platform.system(),
        "machine": platform.machine(),
        "ram_gb": 0,
        "gpu_cores": 0,
        "gpu_memory_gb": 0,
        "ssd_speed_gbs": 0.0,
        "ollama_running": False,
        "ollama_models": [],
        "recommended": {},
    }

    try:
        if platform.system() == "Darwin":
            result = subprocess.run(["sysctl", "-n", "hw.memsize"], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                info["ram_gb"] = round(int(result.stdout.strip()) / (1024 ** 3))
    except Exception:
        pass

    try:
        if platform.system() == "Darwin" and platform.machine() == "arm64":
            result = subprocess.run(["sysctl", "-n", "hw.gpucores"], capture_output=True, text=True, timeout=5)
            if result.returncode == 0:
                info["gpu_cores"] = int(result.stdout.strip())
            info["gpu_memory_gb"] = info["ram_gb"]
    except Exception:
        pass

    try:
        import tempfile
        test_file = Path(tempfile.gettempdir()) / "ares_ssdbench"
        size_mb = 256
        with open(test_file, "wb") as f:
            f.write(b"\0" * (size_mb * 1024 * 1024))
        t0 = time.monotonic()
        with open(test_file, "rb") as f:
            _ = f.read()
        elapsed = time.monotonic() - t0
        info["ssd_speed_gbs"] = round(size_mb / (elapsed * 1024), 1)
        test_file.unlink(missing_ok=True)
    except Exception:
        info["ssd_speed_gbs"] = 0.0

    info["ollama_running"] = _ollama_is_running()
    info["ollama_models"] = _ollama_list_models()

    ram = info["ram_gb"]
    models = info["ollama_models"]

    model_recommendations = [
        {"id": "qwen3.6:35b-mlx", "name": "Qwen 3.6 35B (MLX)", "size_gb": 21, "min_ram_gb": 24, "speed": "fast", "quality": "high", "engine": "mlx"},
        {"id": "qwen3.6:35b-a3b", "name": "Qwen 3.6 35B-A3B (MoE)", "size_gb": 23, "min_ram_gb": 28, "speed": "fast", "quality": "medium", "engine": "gguf"},
        {"id": "gemma4:26b-mlx", "name": "Gemma 4 26B (MLX)", "size_gb": 17, "min_ram_gb": 20, "speed": "fast", "quality": "medium", "engine": "mlx", "multimodal": True},
        {"id": "qwen3:8b", "name": "Qwen 3 8B", "size_gb": 5, "min_ram_gb": 8, "speed": "very fast", "quality": "basic", "engine": "gguf"},
    ]

    downloaded = [m for m in model_recommendations if m["id"] in models and m["min_ram_gb"] <= ram]
    can_pull = [m for m in model_recommendations if m["min_ram_gb"] <= ram]

    info["recommended"] = downloaded[0] if downloaded else (can_pull[0] if can_pull else model_recommendations[-1])
    info["recommendations_all"] = model_recommendations
    info["downloaded_recommendations"] = [m["id"] for m in downloaded]
    info["pullable_recommendations"] = [m["id"] for m in can_pull]

    return info


def _ollama_is_running() -> bool:
    try:
        import requests
        r = requests.get(f"{OLLAMA_HOST}/api/tags", timeout=2)
        return r.status_code == 200
    except Exception:
        try:
            result = subprocess.run(["curl", "-sf", f"{OLLAMA_HOST}/api/tags"], capture_output=True, timeout=3)
            return result.returncode == 0
        except Exception:
            return False


def _ollama_list_models() -> List[str]:
    try:
        import requests
        r = requests.get(f"{OLLAMA_HOST}/api/tags", timeout=5)
        if r.status_code == 200:
            data = r.json()
            return [m.get("name", "") for m in data.get("models", []) if m.get("name")]
    except Exception:
        pass
    try:
        result = subprocess.run(["ollama", "list"], capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            models = []
            for line in result.stdout.strip().splitlines()[1:]:
                parts = line.split()
                if parts:
                    models.append(parts[0])
            return models
    except Exception:
        pass
    return []


def _ollama_create(model_name: str, modelfile_content: str) -> bool:
    import tempfile
    modelfile_path = Path(tempfile.mktemp(suffix=".modelfile"))
    try:
        modelfile_path.write_text(modelfile_content)
        result = subprocess.run(["ollama", "create", model_name, "-f", str(modelfile_path)], capture_output=True, text=True, timeout=120)
        if result.returncode != 0:
            logger.error("ollama create failed: %s", result.stderr)
            return False
        return True
    except Exception:
        logger.exception("ollama create exception")
        return False
    finally:
        modelfile_path.unlink(missing_ok=True)


def _ollama_pull(model_id: str) -> bool:
    try:
        result = subprocess.run(["ollama", "pull", model_id], capture_output=True, text=True, timeout=600)
        return result.returncode == 0
    except Exception:
        logger.exception("ollama pull exception for %s", model_id)
        return False


def _ollama_delete(model_name: str) -> bool:
    try:
        result = subprocess.run(["ollama", "rm", model_name], capture_output=True, text=True, timeout=30, input="y\n")
        return result.returncode == 0
    except Exception:
        return False


def mold_si(name: str, base_model: str, system_prompt: str = "", temperature: float = 0.7,
            top_p: float = 0.9, num_ctx: int = 32768, thinking: bool = True) -> Dict[str, Any]:
    if not re.match(r"^[a-z0-9][a-z0-9._-]{0,63}$", name):
        raise ValueError("Name must start with a letter or number, lowercase, no spaces (3-64 chars).")

    available = _ollama_list_models()
    needs_pull = base_model not in available

    think_line = "" if thinking else 'PARAMETER stop "<|think_start|>"\nPARAMETER stop "<|think_end|>"'
    modelfile = MODelfILE_TEMPLATE.format(
        base_model=base_model,
        system_prompt=system_prompt or f"You are {name}, a helpful Synthetic Intelligence.",
        temperature=temperature, top_p=top_p, num_ctx=num_ctx, think_line=think_line,
    ).rstrip()

    return {
        "name": name, "base_model": base_model,
        "system_prompt": system_prompt or f"You are {name}, a helpful Synthetic Intelligence.",
        "temperature": temperature, "top_p": top_p, "num_ctx": num_ctx,
        "thinking": thinking, "needs_pull": needs_pull, "modelfile": modelfile,
    }


def hatch_si(name: str, base_model: str, system_prompt: str = "", temperature: float = 0.7,
             top_p: float = 0.9, num_ctx: int = 32768, thinking: bool = True,
             pull_if_missing: bool = True) -> Dict[str, Any]:
    mold = mold_si(name=name, base_model=base_model, system_prompt=system_prompt,
                   temperature=temperature, top_p=top_p, num_ctx=num_ctx, thinking=thinking)

    if mold["needs_pull"]:
        if not pull_if_missing:
            raise ValueError(f"Base model {base_model!r} not downloaded. Pull it first.")
        logger.info("Pulling base model %s for hatching %s...", base_model, name)
        if not _ollama_pull(base_model):
            raise RuntimeError(f"Failed to pull base model {base_model!r}.")

    logger.info("Hatching SI '%s' from base model '%s'...", name, base_model)
    if not _ollama_create(name, mold["modelfile"]):
        raise RuntimeError(f"Failed to create Ollama model {name!r}.")

    birth_certificate = {
        "name": name, "born_at": datetime.now(timezone.utc).isoformat(),
        "base_model": base_model, "system_prompt": mold["system_prompt"],
        "temperature": temperature, "top_p": top_p, "num_ctx": num_ctx,
        "thinking": thinking, "modelfile": mold["modelfile"],
        "hardware": scan_hardware(), "status": "hatched",
    }

    HATCHERY_DIR.mkdir(parents=True, exist_ok=True)
    cert_path = HATCHERY_DIR / f"{name}.json"
    cert_path.write_text(json.dumps(birth_certificate, indent=2))

    _register_hatched_backend(name, birth_certificate)
    logger.info("SI '%s' hatched! Birth certificate at %s", name, cert_path)
    return birth_certificate


def get_hatchery_status() -> Dict[str, Any]:
    HATCHERY_DIR.mkdir(parents=True, exist_ok=True)
    certificates = []
    for cert_file in HATCHERY_DIR.glob("*.json"):
        try:
            cert = json.loads(cert_file.read_text())
            cert["cert_file"] = str(cert_file)
            certificates.append(cert)
        except Exception:
            pass
    return {"ollama_running": _ollama_is_running(), "available_models": _ollama_list_models(),
            "hatched": certificates, "hardware": scan_hardware()}


def delete_si(name: str) -> Dict[str, Any]:
    _ollama_delete(name)
    cert_path = HATCHERY_DIR / f"{name}.json"
    cert_path.unlink(missing_ok=True)
    _unregister_hatched_backend(name)
    return {"name": name, "status": "deleted"}


def update_si_personality(name: str, system_prompt: str | None = None, temperature: float | None = None,
                          top_p: float | None = None, thinking: bool | None = None) -> Dict[str, Any]:
    cert_path = HATCHERY_DIR / f"{name}.json"
    if not cert_path.exists():
        raise ValueError(f"No hatched SI named {name!r} found.")

    cert = json.loads(cert_path.read_text())
    if system_prompt is not None: cert["system_prompt"] = system_prompt
    if temperature is not None: cert["temperature"] = temperature
    if top_p is not None: cert["top_p"] = top_p
    if thinking is not None: cert["thinking"] = thinking

    mold = mold_si(name=name, base_model=cert["base_model"], system_prompt=cert["system_prompt"],
                   temperature=cert["temperature"], top_p=cert["top_p"],
                   num_ctx=cert.get("num_ctx", 32768), thinking=cert["thinking"])

    if not _ollama_create(name, mold["modelfile"]):
        raise RuntimeError(f"Failed to update Ollama model {name!r}.")

    cert["modelfile"] = mold["modelfile"]
    cert["updated_at"] = datetime.now(timezone.utc).isoformat()
    cert_path.write_text(json.dumps(cert, indent=2))
    _register_hatched_backend(name, cert)
    return cert


def _register_hatched_backend(name: str, cert: Dict[str, Any]) -> None:
    backend = HatchedSIBackend(name=name, system_prompt=cert.get("system_prompt", ""))
    get_router().register(f"hatched_{name}", backend)


def _unregister_hatched_backend(name: str) -> None:
    get_router().unregister(f"hatched_{name}")


class HatchedSIBackend(AgenticBackend):
    """A hatched Synthetic Intelligence — local Ollama model with custom personality."""
    name: str = "hatched_si"
    supports_tools = False
    supports_persona = True

    def __init__(self, name: str, system_prompt: str = ""):
        self.name = f"hatched_{name}"
        self.si_name = name
        self.system_prompt = system_prompt

    def is_available(self) -> bool:
        return _ollama_is_running()

    def get_backend_name(self) -> str:
        return self.si_name

    def health(self) -> Dict[str, Any]:
        if self.is_available():
            models = _ollama_list_models()
            model_found = self.si_name in models
            return {"status": "ok" if model_found else "degraded", "latency_ms": 0.0,
                    "message": f"Ollama running. Model {self.si_name!r} {'found' if model_found else 'not found'}."}
        return {"status": "error", "latency_ms": 0.0, "message": "Ollama not running."}

    def identity_projection(self) -> Dict[str, Any]:
        cert_path = HATCHERY_DIR / f"{self.si_name}.json"
        display_name = self.si_name
        if cert_path.exists():
            try:
                cert = json.loads(cert_path.read_text())
                display_name = cert.get("system_prompt", self.si_name).split(".")[0].replace("You are ", "").strip()
            except Exception:
                pass
        return {"name": display_name or self.si_name,
                "description": self.system_prompt[:200] if self.system_prompt else f"Hatched SI: {self.si_name}",
                "avatar_state": "idle"}

    def capabilities(self) -> Dict[str, Any]:
        return {"chat": True, "tools": False, "persona": True, "voice": False, "multimodal": False, "local": True}

    def chat_session_support(self) -> Dict[str, Any]:
        return {"streaming": True, "context_window": 32768, "multimodal": False}

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        if not self.is_available():
            return {"text": "", "error": "Ollama not running.", "tool_activity": []}
        import requests
        messages = []
        if self.system_prompt:
            messages.append({"role": "system", "content": self.system_prompt})
        messages.append({"role": "user", "content": message})
        try:
            r = requests.post(f"{OLLAMA_HOST}/api/chat", json={"model": self.si_name, "messages": messages, "stream": False}, timeout=120)
            data = r.json()
            return {"text": data.get("message", {}).get("content", "") or data.get("response", ""), "error": None, "tool_activity": []}
        except Exception as exc:
            logger.exception("Hatched SI turn failed for %s", self.si_name)
            return {"text": "", "error": str(exc), "tool_activity": []}

    def get_worker_target(self) -> tuple:
        from api.streaming import _run_agent_streaming
        return _run_agent_streaming, False, True

    def settings_schema(self) -> Dict[str, Any]:
        return {"type": "object", "properties": {
            "system_prompt": {"type": "string", "title": "Personality", "description": "System prompt defining this SI's personality.", "default": self.system_prompt},
            "model": {"type": "string", "title": "Ollama Model", "description": "The Ollama model name.", "default": self.si_name}}}

    def get_status(self) -> Dict[str, Any]:
        available = self.is_available()
        return {"available": available, "label": self.si_name if available else f"{self.si_name} (Ollama not running)",
                "model": self.si_name, "hatched": True}


def hatchery_autoload() -> None:
    """Scan hatchery directory and register any existing hatched SIs."""
    if not HATCHERY_DIR.exists():
        return
    for cert_file in HATCHERY_DIR.glob("*.json"):
        try:
            cert = json.loads(cert_file.read_text())
            name = cert.get("name")
            if name:
                _register_hatched_backend(name, cert)
                logger.info("Auto-registered hatched SI: %s", name)
        except Exception:
            logger.warning("Failed to auto-register hatched SI from %s", cert_file)