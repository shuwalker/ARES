"""JROS Backend Adapter for ARES.

This adapter wraps the ARES-side JROS gateway bridge
(``api.jros_gateway_chat``). JROS itself is never modified.
"""

from __future__ import annotations

from typing import Any, Dict, cast

from .base import AgenticBackend


class JROSBackend(AgenticBackend):
    name = "jros"
    supports_tools = True
    supports_persona = True
    supports_hybrid = False

    def is_available(self) -> bool:
        try:
            from api.backend_selector import is_jros_available

            return is_jros_available()
        except Exception as exc:
            import logging
            logging.getLogger(__name__).warning(
                "JROSBackend.is_available() probe failed: %s", exc, exc_info=True
            )
            return False

    def get_worker_target(self) -> tuple:
        """Return the JROS streaming worker target."""
        from api.jros_gateway_chat import run_jros_streaming

        return run_jros_streaming, False, True

    def get_backend_name(self) -> str:
        return "JROS"

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        import threading

        from api.jros_gateway_chat import _run_local_jros_turn

        cancel_event = kwargs.get("cancel_event")
        event = cancel_event if hasattr(cancel_event, "is_set") else threading.Event()
        return_text, error, tool_activity = _run_local_jros_turn(
            message,
            session_id,
            cast(Any, event),
        )
        return {"text": return_text, "error": error, "tool_activity": tool_activity}

    def get_status(self) -> Dict[str, Any]:
        available = self.is_available()
        return {
            "available": available,
            "label": "JROS" if available else "JROS (not found)",
            "capabilities": {
                "supports_tools": self.supports_tools,
                "supports_persona": self.supports_persona,
                "supports_hybrid": self.supports_hybrid,
            }
        }
