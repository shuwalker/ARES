"""Strict connection and execution adapter contracts for FastAPI.

Adapters translate ARES requests into connected-system calls.  They do not own
sessions, run registries, journals, worker threads, or terminal processes.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
import queue
from typing import Any, Literal, TYPE_CHECKING

if TYPE_CHECKING:
    from ..schemas import ChatStart


ConnectionState = Literal["connected", "needs_attention", "offline"]


class AdapterError(RuntimeError):
    """A bounded, user-safe adapter failure."""

    def __init__(
        self,
        status_code: int,
        message: str,
        *,
        code: str = "adapter_unavailable",
        context: dict[str, Any] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.message = message
        self.code = code
        self.context = dict(context or {})


@dataclass(frozen=True)
class AdapterHealth:
    state: ConnectionState
    available: bool
    message: str
    details: dict[str, Any] = field(default_factory=dict)

    def as_dict(self) -> dict[str, Any]:
        return {
            "state": self.state,
            "available": self.available,
            "message": self.message,
            "details": dict(self.details),
        }


@dataclass(frozen=True)
class ModelDescriptor:
    id: str
    label: str
    provider: str | None = None
    connection_id: str | None = None

    def as_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "label": self.label,
            "provider": self.provider,
            "connection_id": self.connection_id,
        }


@dataclass
class StreamSubscription:
    channel: Any
    subscriber: queue.Queue
    snapshot: dict[str, Any]
    owner_session_id: str

    def close(self) -> None:
        unsubscribe = getattr(self.channel, "unsubscribe", None)
        if callable(unsubscribe):
            unsubscribe(self.subscriber)


class BaseConnectionAdapter(ABC):
    """Common contract for runtime, provider, and tool connections."""

    adapter_id: str
    display_name: str
    kind: str

    @abstractmethod
    def check_health(self, *, profile: str | None) -> AdapterHealth:
        """Return a normalized, non-secret connection state."""

    @abstractmethod
    def capabilities(self, *, profile: str | None) -> list[str]:
        """Return stable ARES capability identifiers."""

    def connection_record(self, *, profile: str | None, selected: bool = False) -> dict[str, Any]:
        health = self.check_health(profile=profile)
        return {
            "id": self.adapter_id,
            "name": self.display_name,
            "kind": self.kind,
            "selected": selected,
            "health": health.as_dict(),
            "capabilities": self.capabilities(profile=profile),
        }


class BaseLLMAdapter(BaseConnectionAdapter):
    """Execution adapter used by chat controls and WebSocket observation.

    ``stream_chat`` starts a runtime-owned stream and returns its stable ARES
    run/stream handle.  Token iteration remains in the established stream
    channel and run journal; the adapter never starts a second generator loop.
    """

    kind = "runtime"

    @abstractmethod
    async def stream_chat(
        self,
        request: ChatStart,
        *,
        session: Any,
        profile: str | None,
    ) -> dict[str, Any]:
        """Start one streaming chat run without blocking the ASGI event loop."""

    @abstractmethod
    def get_models(self, *, profile: str | None) -> list[ModelDescriptor]:
        """Return models discoverable through this runtime connection."""

    @abstractmethod
    def subscribe_stream(self, stream_id: str, *, owner_session_id: str) -> StreamSubscription | None:
        """Subscribe to the current live observation channel, if present."""

    @abstractmethod
    def replay_stream(
        self,
        stream_id: str,
        *,
        after_event_id: str | None = None,
    ) -> list[dict[str, Any]]:
        """Read durable events after a browser cursor."""

    @abstractmethod
    def stream_status(self, stream_id: str) -> dict[str, Any]:
        """Return normalized live and replay availability."""

    @abstractmethod
    def cancel_stream(self, stream_id: str) -> bool:
        """Request cancellation through the selected runtime control seam."""


class BaseToolAdapter(BaseConnectionAdapter):
    """Capability-provider contract for MCP and later tool connections."""

    kind = "tool"

    @abstractmethod
    def list_tools(self, *, profile: str | None) -> dict[str, Any]:
        """Return a safe, already-known tool inventory without starting servers."""
