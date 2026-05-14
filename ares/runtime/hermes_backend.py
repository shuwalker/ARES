"""Hermes backend — connects ARES to a running Hermes Agent API server.

Hermes is the default brain. This backend sends messages to the local Hermes
API server (usually http://localhost:8321) and returns AgentResponse objects.

The Hermes backend handles:
- Synchronous and streaming message sends
- Health checking and connection management
- Personality prompt injection
- Control tag extraction from responses
"""

from __future__ import annotations

import logging
from typing import Iterator, Optional

import httpx

from ares.core.agent import AgentInterface, AgentResponse, StreamDelta
from ares.core.control_tags import parse_control_tags, tags_to_face_events

logger = logging.getLogger("ares.runtime.hermes_backend")


class HermesBackend(AgentInterface):
    """Brain backend that talks to a local Hermes Agent API server."""

    def __init__(
        self,
        api_url: str = "http://localhost:8321",
        api_key: str = "",
        timeout: float = 120.0,
        **kwargs,
    ):
        self.api_url = api_url.rstrip("/")
        self.api_key = api_key
        self.timeout = timeout
        self._client: Optional[httpx.Client] = None
        self._async_client: Optional[httpx.AsyncClient] = None

    # -- AgentInterface implementation --

    def send(self, message: str, context: Optional[dict] = None) -> AgentResponse:
        """Send a message to Hermes and return the full response."""
        self.connect()
        assert self._client is not None

        payload: dict = {"message": message}
        if context:
            payload["context"] = context

        headers = {}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"

        try:
            resp = self._client.post(
                f"{self.api_url}/v1/chat",
                json=payload,
                headers=headers,
                timeout=self.timeout,
            )
            resp.raise_for_status()
            data = resp.json()
        except httpx.HTTPStatusError as e:
            logger.error("Hermes API error: %s", e)
            return AgentResponse(text=f"[Hermes error: {e.response.status_code}]")
        except httpx.ConnectError as e:
            logger.error("Hermes connection failed: %s", e)
            return AgentResponse(text="[Hermes unreachable — connection refused]")
        except Exception as e:
            logger.error("Hermes backend error: %s", e)
            return AgentResponse(text=f"[Hermes error — {e}]")

        raw_text = data.get("response", "") or data.get("text", "")
        parsed = parse_control_tags(raw_text)

        return AgentResponse(
            text=parsed.clean_text,
            face_state=data.get("face_state", "speaking"),
            expression=data.get("expression", "neutral"),
            tool_events=data.get("tool_events"),
            control_tags={"face": parsed.face_tags, "anim": parsed.anim_tags},
            usage=data.get("usage"),
            session_id=data.get("session_id"),
        )

    def send_streaming(
        self, message: str, context: Optional[dict] = None
    ) -> Iterator[StreamDelta]:
        """Stream deltas from Hermes. Falls back to synchronous if SSE not supported."""
        # TODO: implement SSE streaming when Hermes API supports it
        response = self.send(message, context)
        yield StreamDelta(
            type="complete",
            text=response.text,
            face_state=response.face_state,
            expression=response.expression,
        )

    def interrupt(self, session_id: Optional[str] = None) -> str:
        """Interrupt current generation. Returns any partial response text."""
        self.connect()
        assert self._client is not None

        headers = {}
        if self.api_key:
            headers["Authorization"] = f"Bearer {self.api_key}"

        try:
            payload = {}
            if session_id:
                payload["session_id"] = session_id

            resp = self._client.post(
                f"{self.api_url}/v1/interrupt",
                json=payload,
                headers=headers,
                timeout=5.0,
            )
            resp.raise_for_status()
            data = resp.json()
            return data.get("heard_response", "")
        except Exception as e:
            logger.warning("Interrupt failed: %s", e)
            return ""

    def health(self) -> dict:
        """Check Hermes API server health."""
        try:
            with httpx.Client(timeout=5.0) as client:
                resp = client.get(f"{self.api_url}/health")
                resp.raise_for_status()
                data = resp.json()
                return {
                    "status": "connected",
                    "model": data.get("model", "unknown"),
                    "url": self.api_url,
                }
        except httpx.ConnectError:
            return {"status": "unreachable", "url": self.api_url}
        except Exception as e:
            return {"status": "error", "error": str(e), "url": self.api_url}

    def connect(self) -> None:
        """Establish connection to the Hermes API server."""
        if self._client is None or self._client.is_closed:
            self._client = httpx.Client(timeout=self.timeout)

    def disconnect(self) -> None:
        """Close the connection."""
        if self._client and not self._client.is_closed:
            self._client.close()
            self._client = None