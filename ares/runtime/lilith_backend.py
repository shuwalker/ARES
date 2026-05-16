"""Lilith backend — ZMQ bus connection to a Lilith instance (stub).

Lilith is a future drop-in brain backend. When active, ARES talks to Lilith
over ZMQ pub/sub channels instead of HTTP. This stub establishes the protocol
and interface so the rest of the system can reference it, but does not yet
connect to a real Lilith instance.

To complete: implement ZMQ SUB/PUB socket connections, message serialization,
and the interrupt handshake.
"""

from __future__ import annotations

import logging
from typing import Iterator, Optional

from ares.core.agent import AgentInterface, AgentResponse, StreamDelta

logger = logging.getLogger("ares.runtime.lilith_backend")


class LilithBackend(AgentInterface):
    """Brain backend that talks to a Lilith instance over ZMQ.

    Stub — not yet connected to a real Lilith. Returns a placeholder response.
    """

    def __init__(
        self,
        zmq_host: str = "127.0.0.1",
        input_port: int = 5571,
        output_port: int = 5572,
        **kwargs,
    ):
        self.zmq_host = zmq_host
        self.input_port = input_port
        self.output_port = output_port
        self._connected = False
        logger.info(
            "LilithBackend created (%s:%d/%d) — stub, not yet functional",
            zmq_host,
            input_port,
            output_port,
        )

    def send(self, message: str, context: Optional[dict] = None) -> AgentResponse:
        """Send a message to Lilith. Stub — returns placeholder."""
        logger.warning("LilithBackend.send() called but is a stub — returning placeholder")
        return AgentResponse(
            text="[Lilith backend not yet implemented]",
            face_state="idle",
            expression="neutral",
        )

    def send_streaming(self, message: str, context: Optional[dict] = None) -> Iterator[StreamDelta]:
        """Stream from Lilith. Stub — yields single delta."""
        yield StreamDelta(
            type="complete",
            text="[Lilith backend not yet implemented]",
            face_state="idle",
        )

    def interrupt(self, session_id: Optional[str] = None) -> str:
        """Interrupt Lilith generation. Stub."""
        return ""

    def health(self) -> dict:
        """Check Lilith health. Stub."""
        return {
            "status": "stub",
            "zmq_host": self.zmq_host,
            "input_port": self.input_port,
            "output_port": self.output_port,
        }

    def connect(self) -> None:
        """Establish ZMQ connection. Stub."""
        self._connected = True
        logger.info("LilithBackend.connect() — stub, no real connection")

    def disconnect(self) -> None:
        """Close ZMQ connection. Stub."""
        self._connected = False
