"""ARES Backend Adapter Base — defines the contract for any agent backend.

Pure ARES code. Backends are never modified — ARES wraps them.
Each backend is just {name}_{deployment}. No roles, no opinions.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional


class AgenticBackend(ABC):
    """Abstract base for any agent backend ARES can use."""

    name: str = "unknown"
    supports_tools: bool = True
    supports_persona: bool = False

    @abstractmethod
    def is_available(self) -> bool:
        ...

    @abstractmethod
    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        ...

    def health(self) -> Dict[str, Any]:
        return {"status": "ok" if self.is_available() else "error", "latency_ms": 0.0}

    def identity_projection(self) -> Dict[str, Any]:
        return {"name": self.name, "description": "", "avatar_state": "idle"}

    def capabilities(self) -> Dict[str, Any]:
        return {"chat": True, "tools": self.supports_tools, "persona": self.supports_persona}

    def chat_session_support(self) -> Dict[str, Any]:
        return {"streaming": True, "context_window": 8192, "multimodal": False}

    def tools(self) -> List[Dict[str, Any]]:
        return []

    def settings_schema(self) -> Dict[str, Any]:
        return {"type": "object", "properties": {}}

    def get_worker_target(self) -> tuple:
        from api.streaming import _run_agent_streaming
        return _run_agent_streaming, False, False

    def get_status(self) -> Dict[str, Any]:
        return {"available": self.is_available(), "label": self.name}
