"""Direct Google Gemini cloud adapter — SDK-based, streaming, AgenticBackend-compliant.

Uses the google-generativeai SDK directly (no Hermes proxy, no subprocess).
Supports streaming token-by-token and non-streaming modes.
"""
from __future__ import annotations

import logging
import os
import threading
import time
from typing import Any, Dict, List

from api.providers.agentic_backend import AgenticBackend

logger = logging.getLogger(__name__)


def _api_key(config: dict | None = None) -> str:
    """Resolve Gemini API key: config → env var → ARES secrets."""
    if config:
        key = config.get("api_key")
        if isinstance(key, str) and key.strip():
            return key.strip()
    for env_var in ("GEMINI_API_KEY", "GOOGLE_API_KEY"):
        val = os.environ.get(env_var)
        if val and val.strip():
            return val.strip()
    try:
        from api.config import load_settings
        s = load_settings()
        secrets = s.get("secrets", {})
        for key_name in ("gemini_api_key", "google_api_key"):
            val = secrets.get(key_name)
            if isinstance(val, str) and val.strip():
                return val.strip()
    except Exception:
        pass
    return ""


class GeminiCloudBackend(AgenticBackend):
    """Google Gemini API backend — direct SDK, streaming, no subprocess."""

    name = "gemini_cloud"
    supports_tools = True
    supports_persona = True

    def is_available(self) -> bool:
        return bool(_api_key())

    def get_backend_name(self) -> str:
        return "Google Gemini Cloud"

    def health(self) -> Dict[str, Any]:
        if self.is_available():
            return {"status": "ok", "latency_ms": 0.0, "message": "Gemini API key configured."}
        return {"status": "error", "latency_ms": 0.0, "message": "GEMINI_API_KEY not found."}

    def get_status(self) -> Dict[str, Any]:
        return {"available": self.is_available(), "label": "Google Gemini Cloud"}

    def capabilities(self) -> Dict[str, Any]:
        return {"chat": True, "tools": self.supports_tools, "persona": self.supports_persona}

    def chat_session_support(self) -> Dict[str, Any]:
        return {"streaming": True, "context_window": 128000, "multimodal": True}

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        """Execute one turn via the Google Generative AI SDK.

        Supports streaming (token-by-token via publish callback) and
        non-streaming (full response at once) modes.
        """
        key = _api_key(kwargs.get("config") or kwargs.get("adapter_config"))
        if not key:
            return {"text": "", "error": "No Gemini API key configured.", "tool_activity": []}

        config = kwargs.get("config") or kwargs.get("adapter_config") or {}
        model_name = _cfg_str(config, "model") or kwargs.get("model") or "gemini-2.5-pro"
        # Strip any provider prefix like "gemini_cloud:gemini-2.5-pro"
        if ":" in model_name:
            model_name = model_name.split(":")[-1]

        cancel_event = kwargs.get("cancel_event")
        publish = kwargs.get("publish")  # callable(event, data) for streaming

        try:
            import google.generativeai as genai

            genai.configure(api_key=key)
            model = genai.GenerativeModel(model_name)

            if publish:
                # Streaming mode — emit tokens as they arrive
                accumulated = ""
                response = model.generate_content(message, stream=True)

                for chunk in response:
                    if cancel_event and hasattr(cancel_event, "is_set") and cancel_event.is_set():
                        break
                    if chunk.text:
                        accumulated += chunk.text
                        publish("token", {"text": chunk.text})

                return {"text": accumulated, "error": None, "tool_activity": []}
            else:
                # Non-streaming mode
                response = model.generate_content(message)
                text = response.text if hasattr(response, "text") else ""
                return {"text": text, "error": None, "tool_activity": []}

        except Exception as exc:
            logger.exception("Gemini cloud turn failed")
            return {"text": "", "error": str(exc), "tool_activity": []}


def _cfg_str(config: dict, key: str) -> str | None:
    val = config.get(key)
    return val if isinstance(val, str) and val.strip() else None


# Register with the dynamic backend registry
from .cli_backends import BackendRegistry
BackendRegistry.register(GeminiCloudBackend)


__all__ = ["GeminiCloudBackend"]
