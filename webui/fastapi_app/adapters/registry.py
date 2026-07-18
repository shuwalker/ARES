"""Profile-selected adapter registry and generic dispatcher."""
from __future__ import annotations

from collections.abc import Iterable
from typing import Any

from .base import AdapterError, BaseConnectionAdapter, BaseLLMAdapter, BaseToolAdapter, ModelDescriptor, StreamSubscription
from .frameworks import (
    AresAdapter,
    ClaudeLocalAdapter,
    CodexLocalAdapter,
    CursorLocalAdapter,
    GeminiLocalAdapter,
    GrokLocalAdapter,
    HermesAdapter,
    HybridAdapter,
    JaegerAdapter,
    OllamaLocalAdapter,
    OpenAICloudAdapter,
    OpenCodeLocalAdapter,
    PiLocalAdapter,
    XAICloudAdapter,
    TurnStarter,
)
from .mcp import McpToolAdapter
from ..request_context import profile_scope


_ALIASES = {
    "ares-agent": "ares_local",
    "jaeger": "jros_local",
    "jaegerai": "jros_local",
    "hermes-agent": "hermes_local",
}


class AdapterRegistry:
    """Resolve stateless adapters from Local Profile and session settings."""

    def __init__(
        self,
        *,
        execution_adapters: Iterable[BaseLLMAdapter] | None = None,
        tool_adapters: Iterable[BaseToolAdapter] | None = None,
        turn_starter: TurnStarter | None = None,
    ) -> None:
        if execution_adapters is None:
            execution_adapters = (
                AresAdapter(turn_starter=turn_starter),
                JaegerAdapter(turn_starter=turn_starter),
                HermesAdapter(turn_starter=turn_starter),
                ClaudeLocalAdapter(turn_starter=turn_starter),
                CodexLocalAdapter(turn_starter=turn_starter),
                GeminiLocalAdapter(turn_starter=turn_starter),
                GrokLocalAdapter(turn_starter=turn_starter),
                OpenCodeLocalAdapter(turn_starter=turn_starter),
                CursorLocalAdapter(turn_starter=turn_starter),
                PiLocalAdapter(turn_starter=turn_starter),
                OpenAICloudAdapter(turn_starter=turn_starter),
                XAICloudAdapter(turn_starter=turn_starter),
                OllamaLocalAdapter(turn_starter=turn_starter),
                HybridAdapter(turn_starter=turn_starter),
            )
        if tool_adapters is None:
            tool_adapters = (McpToolAdapter(),)
        execution = list(execution_adapters)
        tools = list(tool_adapters)
        self._execution = {adapter.adapter_id: adapter for adapter in execution}
        self._tools = {adapter.adapter_id: adapter for adapter in tools}

    @staticmethod
    def normalize_id(adapter_id: str) -> str:
        normalized = str(adapter_id or "").strip().lower()
        return _ALIASES.get(normalized, normalized)

    def execution_adapter(self, adapter_id: str) -> BaseLLMAdapter:
        normalized = self.normalize_id(adapter_id)
        adapter = self._execution.get(normalized)
        if adapter is None:
            raise AdapterError(
                400,
                f"Unknown runtime connection: {adapter_id}",
                code="unknown_runtime_connection",
            )
        return adapter

    def tool_adapter(self, adapter_id: str) -> BaseToolAdapter:
        normalized = self.normalize_id(adapter_id)
        adapter = self._tools.get(normalized)
        if adapter is None:
            raise AdapterError(404, "Tool connection not found", code="connection_not_found")
        return adapter

    def for_session(self, session: Any, *, profile: str | None) -> BaseLLMAdapter:
        with profile_scope(profile):
            from api.backend_selector import get_session_backend
            from api.config import get_config

            selected = get_session_backend(session, get_config())
        return self.execution_adapter(selected)

    def connection_records(
        self,
        *,
        profile: str | None,
        session: Any | None = None,
    ) -> dict[str, Any]:
        selected = self.for_session(session, profile=profile).adapter_id if session is not None else self.default_id(profile=profile)
        connections: list[dict[str, Any]] = []
        all_adapters: list[BaseConnectionAdapter] = [*self._execution.values(), *self._tools.values()]
        for adapter in all_adapters:
            try:
                record = adapter.connection_record(
                    profile=profile,
                    selected=adapter.adapter_id == selected,
                )
            except Exception:
                record = {
                    "id": adapter.adapter_id,
                    "name": adapter.display_name,
                    "kind": adapter.kind,
                    "selected": adapter.adapter_id == selected,
                    "health": {
                        "state": "needs_attention",
                        "available": False,
                        "message": "Connection health could not be determined.",
                        "details": {},
                    },
                    "capabilities": [],
                }
            connections.append(record)
        return {"selected": selected, "connections": connections}

    def default_id(self, *, profile: str | None) -> str:
        with profile_scope(profile):
            from api.backend_selector import get_active_backend
            from api.config import get_config

            return self.normalize_id(get_active_backend(get_config()))

    def models(self, adapter_id: str, *, profile: str | None) -> dict[str, Any]:
        adapter = self.execution_adapter(adapter_id)
        try:
            models = adapter.get_models(profile=profile)
        except Exception as exc:
            raise AdapterError(
                503,
                f"Models for {adapter.display_name} are temporarily unavailable.",
                code="model_discovery_unavailable",
                context={"connection_id": adapter.adapter_id},
            ) from exc
        return {
            "connection_id": adapter.adapter_id,
            "models": [model.as_dict() for model in models],
        }
