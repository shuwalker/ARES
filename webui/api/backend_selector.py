"""ARES Backend Selector — routes agent execution to Hermes, JROS, or both.

The core feature of ARES WebUI: the user picks which AI backend runs their agent.

Backends:
  - hermes (default): Hermes Agent in-process — identical to hermes-webui behavior
  - jros: JROS agent — direct JROS agent loop, own model/tools/personality
  - hybrid: Hermes loop + JROS persona injection + JROS tools (additive)

This module is pure routing logic — no side effects on import. Execution
itself happens in api/jros_bridge.py, which talks to an existing JROS
installation over the supported `jaeger bridge` stdio NDJSON protocol.

Availability is checked two ways, in order:
  1. If ARES_JROS_BUS_ENDPOINT is set, ping the optional presence sidecar
     for live model/provider display metadata.
  2. Otherwise, ask api.jros_paths for the installed `jaeger` launcher
     resolved from ARES_JAEGER_HOME, JAEGER_HOME, or the standard installer
     path. ARES never installs a second JROS copy inside its own venv.
"""

from __future__ import annotations

import logging
import os
import time
from typing import Optional

logger = logging.getLogger(__name__)

BACKEND_HERMES = "hermes"
BACKEND_JROS = "jros"
BACKEND_HYBRID = "hybrid"

VALID_BACKENDS = (BACKEND_HERMES, BACKEND_JROS, BACKEND_HYBRID)

_JROS_BUS_ENDPOINT_ENV = "ARES_JROS_BUS_ENDPOINT"

# Cache JROS availability probe (5s TTL — avoids hammering ZMQ/filesystem per request)
_jros_available_cache: Optional[bool] = None
_jros_available_ts: float = 0.0
_jros_presence_info: dict = {}
_JROS_CACHE_TTL = 5.0


def get_active_backend(config: dict) -> str:
    """Read the selected backend from config. Defaults to hermes."""
    raw = str(config.get("ares_backend", "") or "").strip().lower()
    if raw in VALID_BACKENDS:
        return raw
    return BACKEND_HERMES


def _probe_jros_presence_daemon(endpoint: str) -> Optional[dict]:
    """Ping the scripts/jros_presence.py sidecar, if one is configured.

    Returns the daemon's reply dict on success, or None if unreachable
    (daemon not installed, not running, or zmq not available).
    """
    try:
        import zmq

        ctx = zmq.Context.instance()
        sock = ctx.socket(zmq.REQ)
        sock.setsockopt(zmq.LINGER, 0)
        sock.setsockopt(zmq.RCVTIMEO, 1000)
        sock.connect(endpoint)
        sock.send_json({"op": "ping"})
        reply = sock.recv_json()
        sock.close()
        return reply if isinstance(reply, dict) and reply.get("ok") else None
    except Exception:
        return None


def is_jros_available() -> bool:
    """Check whether JROS is usable right now.

    Prefers a live ping to the presence sidecar (see module docstring) when
    ARES_JROS_BUS_ENDPOINT is configured; otherwise falls back to the shared
    bridge launcher availability check.
    """
    global _jros_available_cache, _jros_available_ts, _jros_presence_info
    now = time.time()
    if _jros_available_cache is not None and (now - _jros_available_ts) < _JROS_CACHE_TTL:
        return _jros_available_cache

    result = False
    presence_info: dict = {}
    endpoint = os.environ.get(_JROS_BUS_ENDPOINT_ENV, "").strip()
    if endpoint:
        reply = _probe_jros_presence_daemon(endpoint)
        if reply is not None:
            result = True
            presence_info = {"model": reply.get("model"), "provider": reply.get("provider")}

    if not result and not endpoint:
        try:
            from api.jros_bridge import is_jros_bridge_available

            result = is_jros_bridge_available()
        except Exception as exc:
            logger.warning("JROS bridge availability check failed: %s", exc, exc_info=True)
            result = False

    _jros_available_cache = result
    _jros_available_ts = now
    _jros_presence_info = presence_info
    return result


def backend_status() -> dict:
    """Return current backend availability for UI display."""
    jros_up = is_jros_available()
    status = {
        "hermes": True,  # always available (in-process)
        "jros": jros_up,
        "hybrid": jros_up,  # hybrid needs JROS too
    }
    if jros_up and _jros_presence_info:
        status["jros_model"] = _jros_presence_info.get("model")
        status["jros_provider"] = _jros_presence_info.get("provider")
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