"""Concrete Ares Agent and JaegerAI execution adapters."""

from __future__ import annotations

import asyncio
from collections.abc import Callable
from typing import Any

from .base import AdapterError, AdapterHealth, BaseLLMAdapter, ModelDescriptor, StreamSubscription


TurnStarter = Callable[..., dict[str, Any]]


def _default_turn_starter(session_id: str, message: str, *, source: str) -> dict[str, Any]:
    from api.chat_runtime import start_session_turn

    return dict(start_session_turn(session_id, message, source=source) or {})


class JournaledFrameworkAdapter(BaseLLMAdapter):
    """Shared ARES journal/channel observation for current framework adapters."""

    adapter_id = "unknown"
    display_name = "Unknown runtime"

    def __init__(self, *, backend: Any, turn_starter: TurnStarter | None = None) -> None:
        self.backend = backend
        self._turn_starter = turn_starter or _default_turn_starter

    def capabilities(self, *, profile: str | None) -> list[str]:
        del profile
        raw = self.backend.capabilities()
        mapping = {
            "chat": "conversation",
            "tools": "tool.use",
            "persona": "assistant.identity",
            "voice": "voice",
            "embodiment": "embodiment",
            "robotics": "device.control",
            "hybrid": "multi-runtime",
        }
        return sorted(mapping[key] for key, enabled in raw.items() if enabled and key in mapping)

    async def stream_chat(self, request, *, session: Any, profile: str | None) -> dict[str, Any]:
        try:
            health = self.check_health(profile=profile)
        except Exception as exc:
            raise AdapterError(
                503,
                f"{self.display_name} health could not be determined.",
                code="runtime_health_unavailable",
                context={"connection_id": self.adapter_id},
            ) from exc
        if not health.available:
            raise AdapterError(
                400 if self.adapter_id == "jros_local" else 503,
                health.message,
                code="runtime_unavailable",
                context={"connection_id": self.adapter_id, "state": health.state},
            )
        result = dict(
            await asyncio.to_thread(
                self._turn_starter,
                str(getattr(session, "session_id", request.session_id)),
                request.message,
                source="webui",
            )
            or {}
        )
        status = int(result.pop("_status", 200) or 200)
        if status >= 400:
            raise AdapterError(
                status,
                str(result.get("error") or result.get("message") or "Chat could not start"),
                code=str(result.get("code") or "chat_start_failed"),
                context={
                    key: value
                    for key, value in result.items()
                    if key in {"active_stream_id", "session_id", "type"}
                },
            )
        return result

    def get_models(self, *, profile: str | None) -> list[ModelDescriptor]:
        del profile
        from api.config import get_available_models

        catalog = get_available_models(prefer_cache=True)
        models: list[ModelDescriptor] = []
        seen: set[tuple[str, str]] = set()
        for group in catalog.get("groups") or []:
            if not isinstance(group, dict):
                continue
            provider = str(group.get("provider") or group.get("id") or "").strip() or None
            for bucket in ("models", "extra_models"):
                for raw in group.get(bucket) or []:
                    if isinstance(raw, str):
                        model_id = label = raw
                    elif isinstance(raw, dict):
                        model_id = str(raw.get("id") or raw.get("value") or "").strip()
                        label = str(raw.get("label") or raw.get("name") or model_id).strip()
                    else:
                        continue
                    if not model_id:
                        continue
                    key = (provider or "", model_id)
                    if key in seen:
                        continue
                    seen.add(key)
                    models.append(ModelDescriptor(model_id, label or model_id, provider, self.adapter_id))
        return models

    def subscribe_stream(self, stream_id: str, *, owner_session_id: str) -> StreamSubscription | None:
        from api.config import STREAMS, STREAMS_LOCK

        with STREAMS_LOCK:
            channel = STREAMS.get(stream_id)
        if channel is None:
            return None
        if hasattr(channel, "subscribe_with_snapshot"):
            subscriber, snapshot = channel.subscribe_with_snapshot()
        else:
            subscriber = channel.subscribe() if hasattr(channel, "subscribe") else channel
            snapshot = {}
        return StreamSubscription(channel, subscriber, dict(snapshot or {}), owner_session_id)

    def replay_stream(
        self,
        stream_id: str,
        *,
        after_event_id: str | None = None,
    ) -> list[dict[str, Any]]:
        from api.run_journal import _parse_run_journal_event_id, find_run_summary, read_run_events

        try:
            summary = find_run_summary(stream_id)
        except ValueError:
            return []
        if not summary:
            return []
        cursor_run_id, after_seq = _parse_run_journal_event_id(after_event_id)
        if cursor_run_id and cursor_run_id != stream_id:
            after_seq = None
        journal = read_run_events(
            str(summary.get("session_id") or ""),
            stream_id,
            after_seq=after_seq,
        )
        return [event for event in journal.get("events", []) if isinstance(event, dict)]

    def stream_status(self, stream_id: str) -> dict[str, Any]:
        from api.config import STREAMS, STREAMS_LOCK
        from api.run_journal import find_run_summary

        with STREAMS_LOCK:
            active = stream_id in STREAMS
        summary = find_run_summary(stream_id)
        payload: dict[str, Any] = {
            "active": active,
            "stream_id": stream_id,
            "replay_available": bool(summary),
            "connection_id": self.adapter_id,
        }
        if summary:
            payload["journal"] = {
                key: summary.get(key)
                for key in ("terminal", "terminal_state", "last_event_id", "last_seq")
            }
        return payload

    def cancel_stream(self, stream_id: str) -> bool:
        from api.streaming import cancel_stream

        return bool(cancel_stream(stream_id))


class AresAdapter(JournaledFrameworkAdapter):
    adapter_id = "ares_local"
    display_name = "Ares Agent"

    def __init__(self, *, turn_starter: TurnStarter | None = None) -> None:
        from api.backends.ares import AresBackend

        super().__init__(backend=AresBackend(), turn_starter=turn_starter)

    def check_health(self, *, profile: str | None) -> AdapterHealth:
        del profile
        from api.backend_selector import backend_status

        available = bool(backend_status().get("ares_local"))
        return AdapterHealth(
            "connected" if available else "offline",
            available,
            "Ares Agent is available." if available else "Ares Agent is not installed or reachable.",
        )


class JaegerAdapter(JournaledFrameworkAdapter):
    adapter_id = "jros_local"
    display_name = "JaegerAI"

    def __init__(self, *, turn_starter: TurnStarter | None = None) -> None:
        from api.backends.jros import JROSBackend

        super().__init__(backend=JROSBackend(), turn_starter=turn_starter)

    def check_health(self, *, profile: str | None) -> AdapterHealth:
        del profile
        from api.backend_selector import backend_status
        try:
            from api.jros_companion import companion_available

            companion_ready = bool(companion_available())
        except Exception:
            companion_ready = False
        status = backend_status()
        runtime_available = bool(status.get("jros_local"))
        available = runtime_available and companion_ready
        if available:
            message = "JaegerAI Companion is available."
            state = "connected"
        elif runtime_available:
            message = (
                "Cannot chat: JaegerAI backend is selected but no Companion has been "
                "created. Please complete onboarding or change the backend in settings."
            )
            state = "needs_attention"
        else:
            message = "JaegerAI is not installed or reachable."
            state = "offline"
        details = {
            key.removeprefix("jros_"): value
            for key, value in status.items()
            if key.startswith("jros_") and key not in {"jros_url"}
        }
        return AdapterHealth(state, available, message, details)

    def get_models(self, *, profile: str | None) -> list[ModelDescriptor]:
        del profile
        health = self.check_health(profile=None)
        model_id = str(health.details.get("model") or "").strip()
        provider = str(health.details.get("provider") or "").strip() or None
        if not model_id:
            return []
        return [ModelDescriptor(model_id, model_id, provider, self.adapter_id)]


class HybridAdapter(JournaledFrameworkAdapter):
    adapter_id = "hybrid"
    display_name = "Hybrid"

    def __init__(self, *, turn_starter: TurnStarter | None = None) -> None:
        from api.backends.hybrid import HybridBackend

        super().__init__(backend=HybridBackend(), turn_starter=turn_starter)

    def check_health(self, *, profile: str | None) -> AdapterHealth:
        ares = AresAdapter(turn_starter=self._turn_starter).check_health(profile=profile)
        jaeger = JaegerAdapter(turn_starter=self._turn_starter).check_health(profile=profile)
        available = ares.available and jaeger.available
        state = "connected" if available else "needs_attention"
        return AdapterHealth(
            state,
            available,
            "Ares Agent and JaegerAI are available."
            if available
            else "Hybrid execution requires both Ares Agent and a configured JaegerAI Companion.",
            {"ares": ares.state, "jros_local": jaeger.state},
        )


class HermesAdapter(JournaledFrameworkAdapter):
    adapter_id = "hermes_local"
    display_name = "Hermes Agent"

    def __init__(self, *, turn_starter: TurnStarter | None = None) -> None:
        from api.backends.hermes import HermesBackend

        super().__init__(backend=HermesBackend(), turn_starter=turn_starter)

    def check_health(self, *, profile: str | None) -> AdapterHealth:
        del profile
        from api.backends.hermes import _probe_hermes

        available, version = _probe_hermes()
        if available:
            return AdapterHealth(
                "connected",
                True,
                f"Hermes Agent {version or ''} is available.",
            )
        return AdapterHealth(
            "offline",
            False,
            "Hermes Agent CLI not found. Install with: curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash",
        )

    def get_models(self, *, profile: str | None) -> list[ModelDescriptor]:
        del profile
        # Hermes uses its own model routing from ~/.hermes/config.yaml
        # We report a generic entry so the UI shows something selectable.
        return [ModelDescriptor("hermes-default", "Hermes (default model)", None, self.adapter_id)]


class CliFrameworkAdapter(JournaledFrameworkAdapter):
    """Generic adapter for CLI-based backends (Claude, Codex, Gemini, etc.)."""

    def __init__(self, *, backend_name: str, display_name: str, turn_starter: TurnStarter | None = None) -> None:
        from api.backends.cli_backends import (
            ClaudeLocalBackend, CodexLocalBackend, CursorLocalBackend,
            GeminiLocalBackend, GrokLocalBackend, OpenCodeLocalBackend, PiLocalBackend,
        )
        _BACKEND_MAP = {
            "claude_local": ClaudeLocalBackend,
            "codex_local": CodexLocalBackend,
            "gemini_local": GeminiLocalBackend,
            "grok_local": GrokLocalBackend,
            "opencode_local": OpenCodeLocalBackend,
            "cursor_local": CursorLocalBackend,
            "pi_local": PiLocalBackend,
        }
        backend_cls = _BACKEND_MAP.get(backend_name)
        if backend_cls is None:
            raise ValueError(f"Unknown CLI backend: {backend_name}")
        super().__init__(backend=backend_cls(), turn_starter=turn_starter)
        self.adapter_id = backend_name
        self.display_name = display_name

    def check_health(self, *, profile: str | None) -> AdapterHealth:
        del profile
        available = self.backend.is_available()
        if available:
            return AdapterHealth("connected", True, f"{self.display_name} is available.")
        return AdapterHealth("offline", False, f"{self.display_name} CLI not found on $PATH.")

    def get_models(self, *, profile: str | None) -> list[ModelDescriptor]:
        del profile
        return [ModelDescriptor(f"{self.adapter_id}-default", self.display_name, None, self.adapter_id)]


class ClaudeLocalAdapter(CliFrameworkAdapter):
    def __init__(self, *, turn_starter: TurnStarter | None = None) -> None:
        super().__init__(backend_name="claude_local", display_name="Claude Code", turn_starter=turn_starter)


class CodexLocalAdapter(CliFrameworkAdapter):
    def __init__(self, *, turn_starter: TurnStarter | None = None) -> None:
        super().__init__(backend_name="codex_local", display_name="OpenAI Codex", turn_starter=turn_starter)


class GeminiLocalAdapter(CliFrameworkAdapter):
    def __init__(self, *, turn_starter: TurnStarter | None = None) -> None:
        super().__init__(backend_name="gemini_local", display_name="Google Gemini", turn_starter=turn_starter)


class GrokLocalAdapter(CliFrameworkAdapter):
    def __init__(self, *, turn_starter: TurnStarter | None = None) -> None:
        super().__init__(backend_name="grok_local", display_name="xAI Grok", turn_starter=turn_starter)


class OpenCodeLocalAdapter(CliFrameworkAdapter):
    def __init__(self, *, turn_starter: TurnStarter | None = None) -> None:
        super().__init__(backend_name="opencode_local", display_name="OpenCode", turn_starter=turn_starter)


class CursorLocalAdapter(CliFrameworkAdapter):
    def __init__(self, *, turn_starter: TurnStarter | None = None) -> None:
        super().__init__(backend_name="cursor_local", display_name="Cursor", turn_starter=turn_starter)


class PiLocalAdapter(CliFrameworkAdapter):
    def __init__(self, *, turn_starter: TurnStarter | None = None) -> None:
        super().__init__(backend_name="pi_local", display_name="Pi Coding Agent", turn_starter=turn_starter)


class OpenAICloudAdapter(JournaledFrameworkAdapter):
    adapter_id = "openai_cloud"
    display_name = "OpenAI"

    def __init__(self, *, turn_starter: TurnStarter | None = None) -> None:
        from api.backends.cli_backends import OpenAICloudBackend
        super().__init__(backend=OpenAICloudBackend(), turn_starter=turn_starter)

    def check_health(self, *, profile: str | None) -> AdapterHealth:
        del profile
        available = self.backend.is_available()
        if available:
            return AdapterHealth("connected", True, "OpenAI API key configured.")
        return AdapterHealth("offline", False, "OpenAI API key not found.")

    def get_models(self, *, profile: str | None) -> list[ModelDescriptor]:
        return [ModelDescriptor("gpt-4o", "GPT-4o", "openai", self.adapter_id)]


class XAICloudAdapter(JournaledFrameworkAdapter):
    adapter_id = "xai_cloud"
    display_name = "xAI Grok"

    def __init__(self, *, turn_starter: TurnStarter | None = None) -> None:
        from api.backends.cli_backends import XAICloudBackend
        super().__init__(backend=XAICloudBackend(), turn_starter=turn_starter)

    def check_health(self, *, profile: str | None) -> AdapterHealth:
        del profile
        available = self.backend.is_available()
        if available:
            return AdapterHealth("connected", True, "xAI API key configured.")
        return AdapterHealth("offline", False, "xAI API key not found.")

    def get_models(self, *, profile: str | None) -> list[ModelDescriptor]:
        return [ModelDescriptor("grok-3", "Grok 3", "xai", self.adapter_id)]


class OllamaLocalAdapter(JournaledFrameworkAdapter):
    adapter_id = "ollama_local"
    display_name = "Ollama"

    def __init__(self, *, turn_starter: TurnStarter | None = None) -> None:
        from api.backends.cli_backends import OllamaLocalBackend
        super().__init__(backend=OllamaLocalBackend(), turn_starter=turn_starter)

    def check_health(self, *, profile: str | None) -> AdapterHealth:
        del profile
        available = self.backend.is_available()
        if available:
            return AdapterHealth("connected", True, "Ollama is running.")
        return AdapterHealth("offline", False, "Ollama not reachable on localhost:11434.")

    def get_models(self, *, profile: str | None) -> list[ModelDescriptor]:
        return [ModelDescriptor("llama3.2", "Llama 3.2", "ollama", self.adapter_id)]
