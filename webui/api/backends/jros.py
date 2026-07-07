"""
JROS Backend Adapter for ARES.

This adapter wraps the existing JROS bridge (api.jros_bridge).
JROS itself is never modified — this is pure ARES-side routing.
"""

from __future__ import annotations

from typing import Any, Dict

from .base import AgenticBackend


class JROSBackend(AgenticBackend):
    name = "jros"
    supports_tools = True
    supports_persona = True
    supports_hybrid = False

    def is_available(self) -> bool:
        try:
            from api.jros_bridge import _jros_repo_root
            return (_jros_repo_root() / "jaeger_os").is_dir()
        except Exception:
            return False

    def get_worker_target(self) -> tuple:
        """Return the JROS streaming worker target."""
        from api.jros_bridge import run_jros_streaming
        return run_jros_streaming, False, True

    def get_backend_name(self) -> str:
        return "JROS"

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        # Placeholder — real implementation will call the existing _run_jros_chat_streaming
        return {
            "text": "",
            "error": "JROS adapter not yet wired to legacy bridge",
            "tool_activity": [],
        }

    def get_status(self) -> Dict[str, Any]:
        available = self.is_available()
        return {
            "available": available,
            "label": "JROS" if available else "JROS (not found)",
        }
