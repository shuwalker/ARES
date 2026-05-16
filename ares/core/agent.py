"""ARES agent interface — the swappable brain port.

Every backend (Hermes, Lilith, local Ollama) implements AgentInterface.
The app, face, voice, and MCP skills are the same regardless of which brain
is active.
"""

from __future__ import annotations

import importlib
from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Iterator, Optional


@dataclass
class AgentResponse:
    """Complete response from a brain backend."""

    text: str
    face_state: str = "idle"
    expression: str = "neutral"
    tool_events: Optional[list[dict]] = None
    control_tags: Optional[dict] = None
    usage: Optional[dict] = None
    session_id: Optional[str] = None


@dataclass
class StreamDelta:
    """A single streaming event from a brain backend."""

    type: str  # "delta" | "tool_start" | "tool_end" | "complete" | "error"
    text: str = ""
    tool_name: Optional[str] = None
    tool_result: Optional[str] = None
    face_state: Optional[str] = None
    expression: Optional[str] = None


class AgentInterface(ABC):
    """Abstract brain backend. All concrete backends (Hermes, Lilith, local)
    must implement these methods.
    """

    @abstractmethod
    def send(self, message: str, context: Optional[dict] = None) -> AgentResponse:
        """Send a message and return the full response."""
        ...

    @abstractmethod
    def send_streaming(self, message: str, context: Optional[dict] = None) -> Iterator[StreamDelta]:
        """Send a message and yield streaming deltas."""
        ...

    @abstractmethod
    def interrupt(self, session_id: Optional[str] = None) -> str:
        """Interrupt the current generation. Returns heard_response text."""
        ...

    @abstractmethod
    def health(self) -> dict:
        """Return backend status: model, uptime, capabilities."""
        ...

    @abstractmethod
    def connect(self) -> None:
        """Establish connection to the backend."""
        ...

    @abstractmethod
    def disconnect(self) -> None:
        """Clean shutdown."""
        ...


def load_backend(backend_name: str, config: dict) -> AgentInterface:
    """Factory: instantiate a brain backend by name.

    Lazy-loads the concrete module so missing deps don't blow up imports.
    Supported: "hermes", "lilith", "local".
    """
    module_map = {
        "hermes": "ares.runtime.hermes_backend",
        "lilith": "ares.runtime.lilith_backend",
        "local": "ares.runtime.local_backend",
    }

    module_path = module_map.get(backend_name)
    if module_path is None:
        raise ValueError(f"Unknown backend: {backend_name!r}. " f"Supported: {', '.join(module_map)}")

    module = importlib.import_module(module_path)
    class_name = f"{backend_name.title()}Backend"
    cls = getattr(module, class_name)
    return cls(**config)


__all__ = [
    "AgentResponse",
    "StreamDelta",
    "AgentInterface",
    "load_backend",
]
