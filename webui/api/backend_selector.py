<<<<<<< HEAD
"""ARES runtime selection.

JaegerAI/JROS is the only conversation runtime. Hermes may be installed as an
optional delegated worker that Jaeger calls from ``delegate_task``; it is never
a WebUI backend and never owns ARES sessions, ports, models, or identity.

This module is pure routing logic — no side effects on import. Execution
itself happens in api/jros_gateway_chat.py: local bridge first
(spawns ``jaeger bridge`` from the JaegerAI install), with a legacy gateway
fallback only when ARES_JROS_GATEWAY_URL is explicitly configured.

Availability = a usable local JaegerAI install (mode "local"), or a live
`GET /v1/health` answer from an explicitly configured remote gateway
(mode "gateway").
=======
"""ARES Backend Selector — routes agent execution to any registered backend.

Paperclip pattern: flat registry, agnostic naming. Each backend is
{name}_{deployment}. No roles, no opinions. The UI iterates the map.
>>>>>>> wip/multiagent-orchestrator
"""
from __future__ import annotations

import logging
import os
import shutil
import time
from pathlib import Path
from typing import Optional

from .backends.router import get_router

logger = logging.getLogger(__name__)

<<<<<<< HEAD
BACKEND_JROS = "jros"
# Kept as import-compatible migration constants for old configs and extensions.
# ``normalize_backend`` maps both values to JROS; neither is selectable.
BACKEND_HERMES = "hermes"
BACKEND_HYBRID = "hybrid"
VALID_BACKENDS = (BACKEND_JROS,)
_LEGACY_BACKENDS = frozenset({BACKEND_HERMES, BACKEND_HYBRID})
=======
BACKEND_JROS = "jros_local"

VALID_BACKENDS = (
    "hermes_local", "jros_local",
    "claude_local", "codex_local", "gemini_local", "grok_local",
    "opencode_local", "cursor_local", "pi_local",
    "openai_cloud", "xai_cloud", "gemini_cloud", "gemini_antigravity",
    "ollama_local",
)

_BACKEND_ALIASES = {
    "hermes": "hermes_local",
    "jaeger": "jros_local",
    "jros": "jros_local",
}
>>>>>>> wip/multiagent-orchestrator

_jros_available_cache: Optional[bool] = None
_jros_available_ts = 0.0
_jros_gateway_info: dict = {}
_JROS_CACHE_TTL = 5.0


<<<<<<< HEAD
def normalize_backend(value: object, *, fallback: str = BACKEND_JROS) -> str:
    raw = str(value or "").strip().lower()
    if raw == BACKEND_JROS or raw in _LEGACY_BACKENDS:
        return BACKEND_JROS
    return BACKEND_JROS
=======
def normalize_backend(value: object, *, fallback: str = "") -> str:
    raw_value = str(value or "").strip().lower()
    raw = _BACKEND_ALIASES.get(raw_value, raw_value)
    if raw in VALID_BACKENDS:
        return raw
    return fallback if fallback in VALID_BACKENDS else ""
>>>>>>> wip/multiagent-orchestrator


def get_active_backend(config: dict) -> str:
    """Return the explicitly elected external runtime, or an empty string."""
    return normalize_backend((config or {}).get("ares_backend", ""))


def get_session_backend(session: object, config: dict) -> str:
    default_backend = get_active_backend(config)
    return normalize_backend(getattr(session, "ares_backend", None), fallback=default_backend)


def is_jros_available() -> bool:
    """Bounded, cached JaegerAI *execution* probe shared by every adapter surface.

    A local checkout alone is install-detected, not available. Availability
    requires a live gateway health response so readiness cannot claim
    execution is ready from disk presence alone.
    """

    global _jros_available_cache, _jros_available_ts, _jros_gateway_info
    now = time.monotonic()
    if _jros_available_cache is not None and now - _jros_available_ts < _JROS_CACHE_TTL:
        return _jros_available_cache

    available = False
    details: dict = {}
    try:
        from api.jros_gateway_chat import jros_gateway_health

<<<<<<< HEAD
        # JaegerAI has no HTTP gateway — local bridge is the primary path.
        if local_jros_root() is not None:
            result = True
            presence_info = {"mode": "local"}
            try:
                from api.jros_gateway_chat import local_jros_model

                model = local_jros_model()
                if model:
                    presence_info["model"] = model
                else:
                    # Before the first bridge turn, report the model JaegerAI
                    # will load from its own config rather than leaving the UI
                    # with an unexplained blank model.
                    from api.ares_provider_sync import load_yaml_config
                    from api.jros_paths import jros_config_path

                    external = load_yaml_config(jros_config_path()).get("external_model") or {}
                    if isinstance(external, dict) and external.get("enabled") and external.get("model"):
                        presence_info["model"] = str(external["model"])
                        if external.get("provider"):
                            presence_info["provider"] = str(external["provider"])
            except Exception:
                logger.debug("Local JROS model status unavailable", exc_info=True)
        else:
            # Legacy: remote gateway check for backward compatibility
            reply = jros_gateway_health(timeout=1.0)
            if reply is not None:
                result = True
                presence_info = {
                    "mode": "gateway",
                    "model": reply.get("model"),
                    "provider": reply.get("provider"),
                    "booted": bool(reply.get("booted")),
                    "instance": reply.get("instance"),
                }
=======
        reply = jros_gateway_health(timeout=1.0)
        if reply is not None:
            available = True
            details = {
                "mode": "gateway",
                "model": reply.get("model"),
                "provider": reply.get("provider"),
                "booted": bool(reply.get("booted")),
                "instance": reply.get("instance"),
            }
>>>>>>> wip/multiagent-orchestrator
    except Exception:
        logger.debug("JaegerAI availability probe failed", exc_info=True)

    _jros_available_cache = available
    _jros_available_ts = now
<<<<<<< HEAD
    _jros_gateway_info = presence_info
    return result


def is_hermes_worker_available() -> bool:
    """Whether Jaeger may delegate a subtask to an installed Hermes worker."""
    command = os.getenv("JAEGER_HERMES_COMMAND", "hermes").strip() or "hermes"
    if shutil.which(command) is not None:
        return True
    if command == "hermes":
        return any(
            candidate.is_file()
            for candidate in (
                Path.home() / ".local" / "bin" / "hermes",
                Path("/usr/local/bin/hermes"),
                Path("/opt/homebrew/bin/hermes"),
            )
        )
    return False
=======
    _jros_gateway_info = details
    return available
>>>>>>> wip/multiagent-orchestrator


def backend_status() -> dict:
    """Return current backend availability for UI display."""
    router = get_router()
    status = {
<<<<<<< HEAD
        "jros": jros_up,
        "conversation_owner": BACKEND_JROS,
        "delegated_workers": {
            "hermes": {
                "available": is_hermes_worker_available(),
                "role": "subtask_worker",
                "owns_sessions": False,
                "owns_webui": False,
            }
        },
    }
    if jros_up and _jros_gateway_info:
        status["jros_mode"] = _jros_gateway_info.get("mode")
        status["jros_model"] = _jros_gateway_info.get("model")
        status["jros_provider"] = _jros_gateway_info.get("provider")
        status["jros_booted"] = _jros_gateway_info.get("booted")
        status["jros_instance"] = _jros_gateway_info.get("instance")
    # Surface provider readiness separately from backend readiness. ARES can
    # be healthy while a selected local runtime (for example Ollama) is merely
    # installed but not running—or absent on this machine altogether.
    try:
        from api.ares_provider_sync import load_yaml_config, provider_runtime_status
        from api.jros_paths import jros_config_path
        from api.config import get_config

        active_cfg = get_config() or {}
        model_cfg = active_cfg.get("model") if isinstance(active_cfg.get("model"), dict) else {}
        provider = str((model_cfg or {}).get("provider") or "").strip().lower()
        model = str((model_cfg or {}).get("default") or "").strip()
        base_url = str((model_cfg or {}).get("base_url") or "").strip()
        if provider:
            provider_status = provider_runtime_status(provider, base_url)
            status["model_provider"] = provider
            status["model"] = model or None
            status["model_provider_status"] = provider_status
        external = load_yaml_config(jros_config_path()).get("external_model") or {}
        if isinstance(external, dict) and external.get("enabled"):
            status["jros_model_provider_status"] = provider_runtime_status(
                str(external.get("provider") or ""),
                str(external.get("base_url") or ""),
            )
    except Exception:
        logger.debug("Model provider readiness probe failed", exc_info=True)
    return status


def should_inject_persona(config: dict) -> bool:
    """Jaeger owns and applies its persona; ARES never injects one."""
    return False


def should_register_jros_tools(config: dict) -> bool:
    """JROS already owns its tools; no peer-backend tool injection is needed."""
    return False


def backend_label(backend: str) -> str:
    """Human-readable label for the backend selector dropdown."""
    return {
        BACKEND_JROS: "JaegerAI",
    }.get(backend, backend.title())
=======
        name: backend.is_available()
        for name, backend in router.list_all().items()
        if name not in {"jros", "jros_local"}
    }
    jros_available = is_jros_available()
    status["jros_local"] = jros_available
    if jros_available and _jros_gateway_info:
        for key, value in _jros_gateway_info.items():
            status[f"jros_{key}"] = value
    return status


def backend_label(backend: str) -> str:
    """Human-readable label for the backend selector dropdown."""
    labels = {
        "hermes_local": "Hermes Agent",
        "jros_local": "JROS",
        "claude_local": "Claude Code",
        "codex_local": "OpenAI Codex",
        "gemini_local": "Google Gemini",
        "grok_local": "xAI Grok",
        "opencode_local": "OpenCode",
        "cursor_local": "Cursor",
        "pi_local": "Pi Coding Agent",
        "openai_cloud": "OpenAI",
        "xai_cloud": "xAI Grok",
        "gemini_cloud": "Google Gemini API",
        "gemini_antigravity": "Gemini (Antigravity IDE)",
        "ollama_local": "Ollama",
    }
    return labels.get(backend, backend)
>>>>>>> wip/multiagent-orchestrator
