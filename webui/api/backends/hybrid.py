"""
Hybrid Backend Adapter for ARES.

Composes Ares + JROS into a single backend. Runs the Ares agent loop
with JROS persona injection and JROS tool registration as an additive layer.

This is pure ARES-side routing — neither Ares nor JROS is modified.
"""
from __future__ import annotations

from typing import Any, Dict, List

from .base import AgenticBackend
from .ares import AresBackend
from .jros import JROSBackend


class HybridBackend(AgenticBackend):
    """Composes Ares + JROS into a single agentic backend.

    The Ares loop handles the primary agent execution (tools, skills,
    memory, delegation). JROS adds embodiment, speech, vision, motor
    control, and the skill tree on top.
    """

    name = "hybrid"
    supports_tools = True
    supports_persona = True
    supports_hybrid = True

    def __init__(self) -> None:
        self._ares = AresBackend()
        self._jros = JROSBackend()

    def is_available(self) -> bool:
        """Hybrid is available when both Ares and JROS are available."""
        return self._ares.is_available() and self._jros.is_available()

    def get_worker_target(self) -> tuple:
        """Return the Ares streaming worker (Hybrid uses Ares loop)."""
        return self._ares.get_worker_target()

    def get_backend_name(self) -> str:
        return "Hybrid"

    def health(self) -> Dict[str, Any]:
        ares_health = self._ares.health()
        jros_health = self._jros.health()
        
        status = "ok"
        if ares_health.get("status") == "error" or jros_health.get("status") == "error":
            status = "error"
        elif jros_health.get("status") == "degraded":
            status = "degraded"
            
        return {
            "status": status,
            "latency_ms": max(ares_health.get("latency_ms", 0.0), jros_health.get("latency_ms", 0.0)),
            "message": f"Hybrid runtime status: Ares is {ares_health.get('status')}, JROS is {jros_health.get('status')}",
        }

    def identity_projection(self) -> Dict[str, Any]:
        # Returns JROS character details since JROS defines identity in hybrid mode
        return self._jros.identity_projection()

    def capabilities(self) -> Dict[str, Any]:
        ares_caps = self._ares.capabilities()
        jros_caps = self._jros.capabilities()
        
        # Merge capabilities
        merged = dict(ares_caps)
        merged.update(jros_caps)
        merged["hybrid"] = True
        return merged

    def chat_session_support(self) -> Dict[str, Any]:
        # Return merged settings: supports JROS context window and multimodal features
        return {
            "streaming": True,
            "context_window": min(self._ares.chat_session_support().get("context_window", 32768), 
                                  self._jros.chat_session_support().get("context_window", 8192)),
            "multimodal": True,
        }

    def tools(self) -> List[Dict[str, Any]]:
        # Returns both Ares and JROS tools
        return self._ares.tools() + self._jros.tools()

    def settings_schema(self) -> Dict[str, Any]:
        ares_schema = self._ares.settings_schema().get("properties", {})
        jros_schema = self._jros.settings_schema().get("properties", {})
        
        merged = {}
        merged.update(ares_schema)
        merged.update(jros_schema)
        
        return {
            "type": "object",
            "properties": merged,
        }

    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        """Execute a turn using both Ares and JROS.

        Runs Ares first for the primary agent response, then enriches
        with JROS data when available. Falls back to Ares-only if JROS
        is unreachable at turn time.
        """
        # Run Ares turn
        ares_result = self._ares.run_turn(message, session_id, **kwargs)

        # If JROS is available, enrich with JROS data
        jros_data = {}
        if self._jros.is_available():
            try:
                jros_result = self._jros.run_turn(message, session_id, **kwargs)
                if jros_result and not jros_result.get("error"):
                    jros_data = jros_result
            except Exception:
                pass

        # Merge results — Ares text is primary
        merged_text = ares_result.get("text", "")
        merged_error = ares_result.get("error")
        merged_tool_activity = list(ares_result.get("tool_activity", []))

        # Append JROS tool activity if any
        jros_tool_activity = jros_data.get("tool_activity", [])
        if jros_tool_activity:
            merged_tool_activity.extend(jros_tool_activity)

        return {
            "text": merged_text,
            "error": merged_error,
            "tool_activity": merged_tool_activity,
            "jros_enriched": bool(jros_data),
        }

    def get_status(self) -> Dict[str, Any]:
        ares_avail = self._ares.is_available()
        jros_avail = self._jros.is_available()
        return {
            "available": ares_avail and jros_avail,
            "label": "Hybrid (Ares + JROS)",
            "capabilities": {
                "supports_tools": self.supports_tools,
                "supports_persona": self.supports_persona,
                "supports_hybrid": self.supports_hybrid,
                "ares_available": ares_avail,
                "jros_available": jros_avail,
            },
        }