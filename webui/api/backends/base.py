"""
ARES Backend Adapter Base — defines the contract for peer agentic frameworks.

This lives entirely inside ARES. Hermes and JROS remain untouched peer frameworks.
ARES uses these adapters to route execution without owning or modifying either backend.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional


class AgenticBackend(ABC):
    """Abstract base for any full agentic framework ARES can use."""

    name: str = "unknown"
    supports_tools: bool = True
    supports_persona: bool = False
    supports_hybrid: bool = False

    @abstractmethod
    def is_available(self) -> bool:
        """Return True if this backend can currently execute turns."""
        ...

    @abstractmethod
    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        """
        Execute one agent turn.

        Returns a dict containing at minimum:
            {"text": str, "error": Optional[str], "tool_activity": list}
        """
        ...

    def health(self) -> Dict[str, Any]:
        """Return health details for this backend."""
        return {"status": "ok" if self.is_available() else "error", "latency_ms": 0.0}

    def identity_projection(self) -> Dict[str, Any]:
        """Project the backend's current persona or identity."""
        return {"name": self.get_backend_name(), "description": "", "avatar_state": "idle"}

    def capabilities(self) -> Dict[str, Any]:
        """Return the capabilities dictionary of this backend."""
        return {
            "chat": True,
            "tools": self.supports_tools,
            "persona": self.supports_persona,
            "hybrid": self.supports_hybrid,
            "voice": False,
            "embodiment": False
        }

    def chat_session_support(self) -> Dict[str, Any]:
        """Return metadata for session and chat support."""
        return {"streaming": True, "context_window": 8192, "multimodal": False}

    def tools(self) -> List[Dict[str, Any]]:
        """Return schema definitions of the tools supported/exposed by this backend."""
        return []

    def presence_events(self) -> List[Dict[str, Any]]:
        """Return list of active presence events (avatar animations, speech, etc.)."""
        return []

    def settings_schema(self) -> Dict[str, Any]:
        """Return JSON Schema for the backend's customizable settings."""
        return {
            "type": "object",
            "properties": {}
        }

    def get_worker_target(self) -> tuple:
        """
        Return the (callable, is_gateway, is_jros) tuple for the Hermes
        streaming worker. Subclasses override this to return their own target.
        """
        from api.streaming import _run_agent_streaming
        return _run_agent_streaming, False, False

    def get_backend_name(self) -> str:
        """Return the display name for this backend (e.g. 'Hermes', 'JROS')."""
        return self.name.title() if self.name != "unknown" else self.name.title()

    def get_status(self) -> Dict[str, Any]:
        """Optional richer status for UI display."""
        return {"available": self.is_available(), "label": self.get_backend_name()}


class BackendRouter:
    """
    ARES-side router that decides which peer backend(s) to use.

    Mirrors the ExecutionBackendRouter pattern from the native macOS app.
    """

    def __init__(self, backends: Dict[str, AgenticBackend]):
        self.backends = backends

    def select(self, requested: str) -> AgenticBackend | list[AgenticBackend]:
        if requested == "hybrid":
            return [b for b in self.backends.values() if b.is_available()]
        backend = self.backends.get(requested)
        if backend and backend.is_available():
            return backend
        # Fall back to first available backend
        for name, b in self.backends.items():
            if b.is_available():
                return b
        # Absolute last resort: return the requested backend even if unavailable
        return backend or list(self.backends.values())[0]

    def select_worker(self, requested: str) -> tuple:
        """
        Return the (callable, is_gateway, is_jros) tuple for the requested
        backend.  For 'hybrid' returns the first available backend's worker.
        Falls back to any available backend if the requested one is unavailable.
        """
        if requested == "hybrid":
            available = [b for b in self.backends.values() if b.is_available()]
            if available:
                return available[0].get_worker_target()
        backend = self.backends.get(requested)
        if backend and backend.is_available():
            return backend.get_worker_target()
        # Try the other backend(s)
        for name, b in self.backends.items():
            if name != requested and b.is_available():
                return b.get_worker_target()
        # Last resort: return the default backend even if unavailable
        last = self.backends.get(requested) or list(self.backends.values())[0]
        return last.get_worker_target()

    def get_active_backend_name(self, requested: str) -> str:
        """Return the display name for the active backend."""
        if requested == "hybrid":
            return "Hybrid"
        backend = self.backends.get(requested) or self.backends.get("hermes")
        return backend.get_backend_name() if backend else "Hermes"
