"""
Hermes Backend Adapter for ARES.

This adapter wraps the existing Hermes in-process execution.
Hermes itself is never modified — this is pure ARES-side routing.
"""

from __future__ import annotations

from typing import Any, Dict

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

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        # Placeholder — real implementation will delegate to existing Hermes paths
        # For now we keep the legacy routing until full migration.
        return {
            "text": "",
            "error": "Hermes adapter not yet wired to legacy execution path",
            "tool_activity": [],
        }

    def get_status(self) -> Dict[str, Any]:
        return {"available": True, "label": "Hermes Agent"}
