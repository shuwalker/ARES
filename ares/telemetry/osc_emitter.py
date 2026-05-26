"""Non-blocking OSC telemetry to an avatar render node.

UDP is connectionless and python-osc's SimpleUDPClient does not block on
send — `socket.sendto()` returns immediately once the packet is handed
to the kernel. Errors are swallowed so a missing render node never
interrupts the reasoning loop.

OSC parameter routes follow the VRChat avatar-parameter convention so
the same emitter drives both standalone renderers and VRChat overlays.
"""

from __future__ import annotations

import logging
import socket
from typing import Optional

logger = logging.getLogger("ares.telemetry.osc")


# Avatar parameter routes
ADDR_REASONING_DEPTH = "/avatar/parameters/VisorBrightness"
ADDR_CONFIDENCE = "/avatar/parameters/Confidence"
ADDR_MEMORY_LOAD = "/avatar/parameters/MemoryLoad"


class _NoOpEmitter:
    """Stand-in when OSC telemetry is disabled — every method is a no-op."""

    def emit(self, addr: str, value: float | int | bool) -> None:
        return

    def emit_reasoning_depth(self, value: float) -> None:
        return

    def emit_confidence(self, value: float) -> None:
        return

    def emit_memory_load(self, value: float) -> None:
        return


class OSCEmitter:
    """Fire-and-forget OSC client. Construct once, call from any thread."""

    def __init__(self, host: str, port: int) -> None:
        self.host = host
        self.port = port
        try:
            from pythonosc.udp_client import SimpleUDPClient
        except ImportError as e:
            raise RuntimeError(
                "python-osc is required for OSC telemetry. "
                "Install with `pip install python-osc`."
            ) from e
        self._client = SimpleUDPClient(host, port)

    def emit(self, addr: str, value: float | int | bool) -> None:
        try:
            self._client.send_message(addr, value)
        except (OSError, socket.error) as e:
            logger.debug("OSC emit %s=%r failed: %s", addr, value, e)

    def emit_reasoning_depth(self, value: float) -> None:
        self.emit(ADDR_REASONING_DEPTH, float(value))

    def emit_confidence(self, value: float) -> None:
        self.emit(ADDR_CONFIDENCE, float(value))

    def emit_memory_load(self, value: float) -> None:
        self.emit(ADDR_MEMORY_LOAD, float(value))


_cached: Optional[OSCEmitter | _NoOpEmitter] = None


def get_emitter() -> OSCEmitter | _NoOpEmitter:
    """Return a cached emitter built from AresConfig.telemetry."""
    global _cached
    if _cached is not None:
        return _cached

    from ares.runtime.config import get_config

    cfg = get_config().telemetry
    if not cfg.osc_enabled:
        _cached = _NoOpEmitter()
    else:
        _cached = OSCEmitter(cfg.osc_host, cfg.osc_port)
    return _cached


def reset_emitter() -> None:
    """Clear the cached emitter — used by tests and config reload."""
    global _cached
    _cached = None
