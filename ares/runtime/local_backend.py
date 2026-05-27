"""Local backend — direct Ollama inference for air-gapped / offline mode.

Uses the local Ollama server for chat completions. Minimal dependencies,
no streaming, no tool use. This is the fallback brain when no other backend
is available.
"""

from __future__ import annotations

import logging
from typing import Iterator, Optional

import httpx

from ares.core.agent import AgentInterface, AgentResponse, StreamDelta
from ares.core.control_tags import parse_control_tags

logger = logging.getLogger("ares.runtime.local_backend")


class LocalBackend(AgentInterface):
    """Brain backend that talks directly to a local Ollama server."""

    def __init__(
        self,
        model: str = "gemma3:12b",
        ollama_url: str = "http://localhost:11434",
        timeout: float = 300.0,
        **kwargs,
    ):
        self.model = model
        self.ollama_url = ollama_url.rstrip("/")
        self.timeout = timeout
        self._client: Optional[httpx.Client] = None

    def send(self, message: str, context: Optional[dict] = None) -> AgentResponse:
        """Send a message to local Ollama and return the response."""
        self.connect()
        assert self._client is not None

        system_prompt = context.get("system_prompt", "") if context else ""
        messages = []
        if system_prompt:
            messages.append({"role": "system", "content": system_prompt})
        messages.append({"role": "user", "content": message})

        payload = {
            "model": self.model,
            "messages": messages,
            "stream": False,
        }

        # Fast-path gate (Lilith pattern) — placeholder.
        # If cfg.agent.fast_path_enabled, a lightweight model (llama3.2:3b)
        # would intercept short/simple turns here and short-circuit the call,
        # returning early before engaging the full agent. Not yet implemented.
        try:
            resp = self._client.post(
                f"{self.ollama_url}/api/chat",
                json=payload,
                timeout=self.timeout,
            )
            resp.raise_for_status()
            data = resp.json()
        except httpx.ConnectError:
            logger.error("Ollama connection failed at %s", self.ollama_url)
            return AgentResponse(
                text="[Local backend unreachable — is Ollama running?]",
                face_state="error",
            )
        except Exception as e:
            logger.error("Local backend error: %s", e)
            return AgentResponse(text=f"[Local backend error — {e}]")

        raw_text = data.get("message", {}).get("content", "")
        parsed = parse_control_tags(raw_text)

        return AgentResponse(
            text=parsed.clean_text,
            face_state="speaking",
            expression="neutral",
            control_tags={"face": parsed.face_tags, "anim": parsed.anim_tags},
            usage=data.get("eval_count"),
        )

    def send_streaming(self, message: str, context: Optional[dict] = None) -> Iterator[StreamDelta]:
        """Stream from local Ollama. Falls back to synchronous."""
        response = self.send(message, context)
        yield StreamDelta(
            type="complete",
            text=response.text,
            face_state=response.face_state,
            expression=response.expression,
        )

    def interrupt(self, session_id: Optional[str] = None) -> str:
        """Interrupt local generation. Ollama doesn't support this well."""
        return ""

    def health(self) -> dict:
        """Check Ollama health."""
        try:
            with httpx.Client(timeout=5.0) as client:
                resp = client.get(f"{self.ollama_url}/api/tags")
                resp.raise_for_status()
                models = [m.get("name", "") for m in resp.json().get("models", [])]
                return {
                    "status": "connected",
                    "url": self.ollama_url,
                    "model": self.model,
                    "available_models": models,
                }
        except httpx.ConnectError:
            return {"status": "unreachable", "url": self.ollama_url}
        except Exception as e:
            return {"status": "error", "error": str(e), "url": self.ollama_url}

    def connect(self) -> None:
        """Create HTTP client."""
        if self._client is None or self._client.is_closed:
            self._client = httpx.Client(timeout=self.timeout)

    def disconnect(self) -> None:
        """Close HTTP client."""
        if self._client and not self._client.is_closed:
            self._client.close()
            self._client = None
