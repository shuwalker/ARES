"""ARES Companion runtime compatibility layer.

JaegerAI owns every primary conversation. Historical ``hermes`` and ``hybrid``
values remain readable while old sessions migrate, but normalize to JROS and
cannot alter turn ownership. Hermes is an optional task worker, not a peer
conversation backend. See docs/architecture/SINGLE_COMPANION_RUNTIME.md.

Backends:
  - jros (default): JaegerAI is the required Companion runtime — the brain,
    memory, character, and local model that "name your Companion" onboarding
    creates. Turns run through the local ``jaeger bridge`` over stdio (NDJSON).
    JaegerAI has no HTTP gateway; the bridge is the primary and only path.
    See api/jros_gateway_chat.py.
  - hermes: Hermes Agent in-process — an optional addition for coding/
    terminal/skills capability, identical to hermes-webui behavior. Only
    meaningful once the operator has installed Hermes (it is not installed
    by default; see webui/scripts/install.sh --with-hermes).
  - hybrid: JaegerAI persona/tools layered onto the Hermes loop (additive).
    Currently hidden in the UI while the mode is being defined; the value
    stays valid server-side so existing configs keep working.

This module is pure routing logic — no side effects on import. Execution
itself happens in api/jros_gateway_chat.py: local bridge first
(spawns ``jaeger bridge`` from the JaegerAI install), with a legacy gateway
fallback only when ARES_JROS_GATEWAY_URL is explicitly configured.

Availability = a usable local JaegerAI install (mode "local"), or a live
`GET /v1/health` answer from an explicitly configured remote gateway
(mode "gateway").
"""

from __future__ import annotations

import logging
import time
from typing import Optional

import yaml

logger = logging.getLogger(__name__)

BACKEND_HERMES = "hermes"
BACKEND_JROS = "jros"
BACKEND_HYBRID = "hybrid"

VALID_BACKENDS = (BACKEND_HERMES, BACKEND_JROS, BACKEND_HYBRID)

# Cache JROS availability probe (5s TTL — avoids an HTTP round-trip per request)
_jros_available_cache: Optional[bool] = None
_jros_available_ts: float = 0.0
_jros_gateway_info: dict = {}
_JROS_CACHE_TTL = 5.0


def normalize_backend(value: object, *, fallback: str = BACKEND_JROS) -> str:
    """Return the sole Companion runtime.

    ``value`` and ``fallback`` are accepted only for compatibility with saved
    sessions and older callers.
    """
    return BACKEND_JROS


def get_active_backend(config: dict) -> str:
    """Read the default backend from config.

    The config value is the default for new/unset chats. Individual sessions may
    carry their own ``ares_backend`` override.
    """
    return normalize_backend((config or {}).get("ares_backend", ""))


def get_session_backend(session: object, config: dict) -> str:
    """Return the backend selected for one chat session."""
    default_backend = get_active_backend(config)
    return normalize_backend(getattr(session, "ares_backend", None), fallback=default_backend)


def is_jros_available() -> bool:
    """Check whether JaegerAI is usable right now.

    Prefers a local JaegerAI install that the bridge can spawn (mode "local");
    falls back to a live /v1/health answer only when an explicit remote gateway
    is configured (backward compatibility, mode "gateway")."""
    global _jros_available_cache, _jros_available_ts, _jros_gateway_info
    now = time.time()
    if _jros_available_cache is not None and (now - _jros_available_ts) < _JROS_CACHE_TTL:
        return _jros_available_cache

    result = False
    presence_info: dict = {}
    try:
        from api.jros_gateway_chat import jros_gateway_health, local_jros_root

        # JaegerAI has no HTTP gateway — local bridge is the primary path.
        if local_jros_root() is not None:
            result = True
            presence_info = {"mode": "local"}
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
    except Exception:
        logger.debug("JaegerAI availability probe failed", exc_info=True)

    _jros_available_cache = result
    _jros_available_ts = now
    _jros_gateway_info = presence_info
    return result


def _is_hermes_available() -> bool:
    """Hermes is an optional addition — only available once installed."""
    try:
        from api.config import _HERMES_FOUND

        return bool(_HERMES_FOUND)
    except Exception:
        logger.debug("Hermes availability probe failed", exc_info=True)
        return False


def _configured_jros_runtime() -> dict:
    """Read the configured Companion model without booting another runtime."""
    try:
        from api.jros_paths import jros_config_path, jros_instance_name

        path = jros_config_path()
        raw = yaml.safe_load(path.read_text(encoding="utf-8")) if path.exists() else {}
        cfg = raw if isinstance(raw, dict) else {}
        external = cfg.get("external_model") if isinstance(cfg.get("external_model"), dict) else {}
        local = cfg.get("model") if isinstance(cfg.get("model"), dict) else {}
        if external.get("enabled"):
            return {
                "instance": jros_instance_name(),
                "model": str(external.get("model") or "").strip() or None,
                "provider": str(external.get("provider") or "").strip() or None,
                "transport": "external",
                "config_path": str(path),
            }
        return {
            "instance": jros_instance_name(),
            "model": str(local.get("model_path") or "").strip() or None,
            "provider": str(local.get("backend") or "").strip() or None,
            "transport": "in_process",
            "config_path": str(path),
        }
    except Exception:
        logger.debug("Failed to read configured JaegerAI runtime", exc_info=True)
        return {}


def backend_status() -> dict:
    """Return current backend availability for UI display."""
    jros_up = is_jros_available()
    runtime = _configured_jros_runtime()
    status = {
        "hermes": _is_hermes_available(),  # optional addition, not guaranteed
        "jros": jros_up,
        "hybrid": False,
        "companion": {
            "runtime": "jaeger",
            "available": jros_up,
            **runtime,
        },
    }
    if jros_up and _jros_gateway_info:
        status["jros_mode"] = _jros_gateway_info.get("mode")
        status["jros_model"] = _jros_gateway_info.get("model")
        status["jros_provider"] = _jros_gateway_info.get("provider")
        status["jros_booted"] = _jros_gateway_info.get("booted")
        status["jros_instance"] = _jros_gateway_info.get("instance")
    if runtime:
        status["jros_model"] = runtime.get("model")
        status["jros_provider"] = runtime.get("provider")
        status["jros_instance"] = runtime.get("instance")
    return status


def should_inject_persona(config: dict) -> bool:
    """True if the current backend mode should inject JROS persona.

    Persona injection happens in:
      - hermes: No (pure Hermes behavior)
      - jros: No (JROS handles its own persona)
      - hybrid: Yes (Hermes loop + JROS persona)
    """
    return False


def should_register_jros_tools(config: dict) -> bool:
    """True if JROS tools should be registered into the Hermes agent.

    JROS tools are registered in:
      - hermes: No
      - jros: No (JROS has its own tool system)
      - hybrid: Yes (Hermes agent gains JROS tools)
    """
    return False


def backend_label(backend: str) -> str:
    """Human-readable label for the backend selector dropdown."""
    return {
        BACKEND_HERMES: "JaegerAI Companion (migrated from Hermes)",
        BACKEND_JROS: "JaegerAI Companion",
        BACKEND_HYBRID: "JaegerAI Companion (migrated from Hybrid)",
    }.get(backend, backend.title())
