"""ARES Backend Selector — routes agent execution to Hermes or JROS.

The core feature of ARES WebUI: the user picks which AI backend runs their agent.

Backends:
  - hermes (default): Hermes Agent in-process — identical to hermes-webui behavior
  - jros: JROS agent — turns run on a JROS gateway server (`jaeger gateway`),
    local or remote, over HTTP. See api/jros_gateway_chat.py.
  - hybrid: Hermes loop + JROS persona injection + JROS tools (additive).
    Currently hidden in the UI while the mode is being defined; the value
    stays valid server-side so existing configs keep working.

This module is pure routing logic — no side effects on import. Execution
itself happens in api/jros_gateway_chat.py: gateway first (POST to
ARES_JROS_GATEWAY_URL, default localhost:8643 — same integration shape as
the Hermes Gateway bridge in api/gateway_chat.py), and when no gateway is
reachable, an in-process fallback boots the local ARES_JROS_DIR checkout.

Availability = a live `GET /v1/health` answer from the gateway (mode
"gateway"), else a usable local checkout (mode "local"). A JROS on another
machine is just a different base URL.
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


def get_active_backend(config: dict) -> str:
    """Read the selected backend from config. Defaults to hermes."""
    raw = str(config.get("ares_backend", "") or "").strip().lower()
    if raw in VALID_BACKENDS:
        return raw
    return BACKEND_HERMES


def is_jros_available() -> bool:
    """Check whether JROS is usable right now.

    Prefers a live /v1/health answer from the configured JROS gateway
    (mode "gateway"); otherwise a local ARES_JROS_DIR checkout that the
    in-process fallback could boot counts too (mode "local")."""
    global _jros_available_cache, _jros_available_ts, _jros_gateway_info
    now = time.time()
    if _jros_available_cache is not None and (now - _jros_available_ts) < _JROS_CACHE_TTL:
        return _jros_available_cache

    result = False
    presence_info: dict = {}
    try:
        from api.jros_gateway_chat import jros_gateway_health, local_jros_root

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
        elif local_jros_root() is not None:
            result = True
            presence_info = {"mode": "local"}
    except Exception:
        logger.debug("JROS availability probe failed", exc_info=True)

    _jros_available_cache = result
    _jros_available_ts = now
    _jros_gateway_info = presence_info
    return result


def backend_status() -> dict:
    """Return current backend availability for UI display."""
    jros_up = is_jros_available()
    status = {
        "hermes": True,  # always available (in-process)
        "jros": jros_up,
        "hybrid": jros_up,  # hybrid needs JROS too
    }
    if jros_up and _jros_gateway_info:
        status["jros_mode"] = _jros_gateway_info.get("mode")
        status["jros_model"] = _jros_gateway_info.get("model")
        status["jros_provider"] = _jros_gateway_info.get("provider")
        status["jros_booted"] = _jros_gateway_info.get("booted")
        status["jros_instance"] = _jros_gateway_info.get("instance")
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
        BACKEND_HERMES: "Hermes",
        BACKEND_JROS: "JROS",
        BACKEND_HYBRID: "Hybrid",
    }.get(backend, backend.title())
