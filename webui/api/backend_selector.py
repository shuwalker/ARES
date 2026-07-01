"""ARES Backend Selector — routes agent execution to Hermes, JROS, or both.

The core feature of ARES WebUI: the user picks which AI backend runs their agent.

Backends:
  - hermes (default): Hermes Agent in-process — identical to hermes-webui behavior
  - jros: JROS agent — direct JROS agent loop, own model/tools/personality
  - hybrid: Hermes loop + JROS persona injection + JROS tools (additive)

This module is pure routing logic — no side effects on import. The actual
JROS bridge (ZMQ client) is in api/jros_bridge.py and only loads when needed.
"""

from __future__ import annotations

import logging
import os
from typing import Optional

logger = logging.getLogger(__name__)

BACKEND_HERMES = "hermes"
BACKEND_JROS = "jros"
BACKEND_HYBRID = "hybrid"

VALID_BACKENDS = (BACKEND_HERMES, BACKEND_JROS, BACKEND_HYBRID)

# JROS bus endpoint — ZMQ IPC socket
_JROS_BUS_ENDPOINT = os.environ.get(
    "ARES_JROS_BUS_ENDPOINT", "ipc:///tmp/jros.bus"
)

# Cache JROS availability probe (5s TTL to avoid hammering ZMQ on every request)
_jros_available_cache: Optional[bool] = None
_jros_available_ts: float = 0.0
_JROS_CACHE_TTL = 5.0


def get_active_backend(config: dict) -> str:
    """Read the selected backend from config. Defaults to hermes."""
    raw = str(config.get("ares_backend", "") or "").strip().lower()
    if raw in VALID_BACKENDS:
        return raw
    return BACKEND_HERMES


def is_jros_available() -> bool:
    """Check if JROS daemon is reachable on the ZMQ IPC bus.

    Non-blocking probe with 1s timeout. Cached for 5 seconds to avoid
    creating a ZMQ context on every API call.
    """
    import time

    global _jros_available_cache, _jros_available_ts
    now = time.time()
    if _jros_available_cache is not None and (now - _jros_available_ts) < _JROS_CACHE_TTL:
        return _jros_available_cache

    try:
        import zmq
        ctx = zmq.Context.instance()
        sock = ctx.socket(zmq.REQ)
        sock.setsockopt(zmq.LINGER, 0)
        sock.setsockopt(zmq.RCVTIMEO, 1000)  # 1s timeout
        sock.connect(_JROS_BUS_ENDPOINT)
        # Ping — JROS broker responds to "ping" on the bus
        sock.send_json({"op": "ping"})
        reply = sock.recv_json()  # raises if timeout
        sock.close()
        result = bool(reply.get("ok", False))
    except Exception:
        # ZMQ not installed, bus not running, timeout — all mean "not available"
        result = False

    _jros_available_cache = result
    _jros_available_ts = now
    return result


def backend_status() -> dict:
    """Return current backend availability for UI display."""
    jros_up = is_jros_available()
    return {
        "hermes": True,  # always available (in-process)
        "jros": jros_up,
        "hybrid": jros_up,  # hybrid needs JROS too
        "jros_endpoint": _JROS_BUS_ENDPOINT if jros_up else None,
    }


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