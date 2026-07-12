"""
Hermes Backend Adapter for ARES.

This adapter wraps the existing Hermes in-process execution.
Hermes itself is never modified — this is pure ARES-side routing.
"""

from __future__ import annotations

from typing import Any, Dict, List

from .base import AgenticBackend


class HermesBackend(AgenticBackend):
    name = "hermes"
    supports_tools = True
    supports_persona = False
    supports_hybrid = False

    def is_available(self) -> bool:
        # Hermes is always available when the WebUI is running
        return True

    def get_worker_target(self) -> tuple:
        """Return the Hermes streaming worker target."""
        from api.streaming import _run_agent_streaming
        return _run_agent_streaming, False, False

    def get_backend_name(self) -> str:
        return "Hermes"

    def health(self) -> Dict[str, Any]:
        return {"status": "ok", "latency_ms": 0.0, "message": "In-process runtime ready"}

    def identity_projection(self) -> Dict[str, Any]:
        from api.config import get_config
        cfg = get_config()
        bot_name = (cfg.get("agent") or {}).get("name") or "Hermes"
        return {
            "name": bot_name,
            "description": "Hermes Agent in-process runtime",
            "avatar_state": "idle",
        }

    def capabilities(self) -> Dict[str, Any]:
        return {
            "chat": True,
            "tools": self.supports_tools,
            "persona": self.supports_persona,
            "hybrid": self.supports_hybrid,
            "voice": True,
            "embodiment": False,
        }

    def chat_session_support(self) -> Dict[str, Any]:
        return {"streaming": True, "context_window": 32768, "multimodal": False}

    def tools(self) -> List[Dict[str, Any]]:
        try:
            from api.ares_tools import ARES_TOOL_DEFS
            return [
                {
                    "name": t["name"],
                    "description": t["description"],
                    "parameters": t["args_model"].schema() if hasattr(t["args_model"], "schema") else (t["args_model"].model_json_schema() if hasattr(t["args_model"], "model_json_schema") else {}),
                }
                for t in ARES_TOOL_DEFS
            ]
        except Exception:
            return []

    def settings_schema(self) -> Dict[str, Any]:
        return {
            "type": "object",
            "properties": {
                "temperature": {
                    "type": "number",
                    "title": "Temperature",
                    "default": 0.7,
                    "minimum": 0.0,
                    "maximum": 2.0,
                },
                "system_instructions": {
                    "type": "string",
                    "title": "System Instructions",
                    "default": "",
                },
            },
        }

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        """
        Execute one agent turn via the Hermes streaming path.

        The streaming path is the primary execution path for Hermes
        (used by the WebUI chat). This synchronous wrapper creates a
        temporary stream channel, runs the agent, and collects the
        response text.

        Falls back to the existing streaming pathway when called
        without a real stream channel by returning a guidance message.
        """
        from api.config import create_stream_channel, register_stream_owner
        from api.streaming import _run_agent_streaming
        from api.config import STREAMS, STREAMS_LOCK
        import threading
        import uuid

        stream_id = f"hermes-sync-{uuid.uuid4().hex[:12]}"
        channel = create_stream_channel()
        with STREAMS_LOCK:
            STREAMS[stream_id] = channel
        register_stream_owner(stream_id, session_id)

        # Subscribe a queue so we can read events
        event_queue = channel.subscribe()

        # Default model from config
        from api.config import get_config
        cfg = get_config()
        model = str((cfg.get("model") or {}).get("default", "")) or "hermes-default"

        result = {"text": "", "error": None, "tool_activity": []}

        def _run():
            try:
                _run_agent_streaming(
                    session_id,
                    message,
                    model,
                    "default",
                    stream_id,
                    attachments=None,
                )
            except Exception as exc:
                result["error"] = str(exc)

        thread = threading.Thread(target=_run, daemon=True)
        thread.start()

        # Collect events from the stream channel
        import time
        deadline = time.time() + 120  # 2-minute timeout
        collected_text = []
        tool_activity = []
        while time.time() < deadline:
            try:
                event = event_queue.get(timeout=0.5)
            except Exception:
                if not thread.is_alive():
                    break
                continue
            if event is None:
                continue
            event_type = str(event[0] if isinstance(event, (list, tuple)) else event.get("type", ""))
            if event_type == "token":
                payload = event[1] if isinstance(event, (list, tuple)) and len(event) > 1 else event
                if isinstance(payload, dict):
                    collected_text.append(payload.get("text", ""))
            elif event_type == "tool":
                tool_activity.append(event[1] if isinstance(event, (list, tuple)) and len(event) > 1 else event)
            elif event_type == "done":
                break
            elif event_type == "error":
                result["error"] = str(event[1] if isinstance(event, (list, tuple)) and len(event) > 1 else event)
                break
            elif event_type == "stream_end":
                break

        thread.join(timeout=5)
        result["text"] = "".join(collected_text)
        result["tool_activity"] = tool_activity

        # Cleanup
        channel.unsubscribe(event_queue)
        with STREAMS_LOCK:
            STREAMS.pop(stream_id, None)
        from api.config import unregister_stream_owner
        unregister_stream_owner(stream_id)

        return result

    def get_status(self) -> Dict[str, Any]:
        return {
            "available": True,
            "label": "Hermes Agent",
            "capabilities": {
                "supports_tools": self.supports_tools,
                "supports_persona": self.supports_persona,
                "supports_hybrid": self.supports_hybrid,
            }
        }
