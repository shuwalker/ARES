"""ARES Backend Selector — routes agent execution to JaegerAI or Hermes.

The core feature of ARES WebUI: the user picks which AI backend runs their agent.

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
    raw = str(value or "").strip().lower()
    if raw in VALID_BACKENDS:
        return raw
    return fallback if fallback in VALID_BACKENDS else BACKEND_JROS


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


def backend_status() -> dict:
    """Return current backend availability for UI display."""
    jros_up = is_jros_available()
    status = {
        "hermes": _is_hermes_available(),  # optional addition, not guaranteed
        "jros": jros_up,
        "hybrid": jros_up and _is_hermes_available(),  # hybrid needs both
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
    """True if the current backend mode should inject JROS persona.

    Persona injection happens in:
      - hermes: No (pure Hermes behavior)
      - jros: No (JROS handles its own persona)
      - hybrid: Yes (Hermes loop + JROS persona)
    """
    return get_active_backend(config) == BACKEND_HYBRID


def should_register_jros_tools(config: dict) -> bool:
    """True if JROS tools should be registered into the Hermes agent.

    JROS tools are registered in:
      - hermes: No
      - jros: No (JROS has its own tool system)
      - hybrid: Yes (Hermes agent gains JROS tools)
    """
    return get_active_backend(config) == BACKEND_HYBRID and is_jros_available()


def backend_label(backend: str) -> str:
    """Human-readable label for the backend selector dropdown."""
    return {
        BACKEND_HERMES: "Hermes Agent",
        BACKEND_JROS: "JROS",
        BACKEND_HYBRID: "Hybrid",
    }.get(backend, backend.title())
