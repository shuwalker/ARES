"""Concrete adapters for external execution runtimes."""

from __future__ import annotations

import asyncio
from collections.abc import Callable
from typing import Any

from .base import AdapterError, AdapterHealth, BaseLLMAdapter, ModelDescriptor, StreamSubscription


TurnStarter = Callable[..., dict[str, Any]]


def _descriptors_from_inventory(inventory: dict[str, Any] | None, *, connection_id: str) -> list[ModelDescriptor]:
    """Convert catalog.model_entry shape to ModelDescriptor for UI display.

    Returns empty list when inventory is None or has no models (never a fake
    placeholder ID). Callers should treat None and [] identically.
    """
    if not inventory or not isinstance(inventory, dict):
        return []
    models: list[ModelDescriptor] = []
    for entry in inventory.get("models") or []:
        if not isinstance(entry, dict):
            continue
        model_id = str(entry.get("id") or "").strip()
        label = str(entry.get("label") or model_id).strip()
        provider = entry.get("provider")  # can be None
        if model_id:
            models.append(ModelDescriptor(model_id, label or model_id, provider, connection_id))
    return models


def _provider_probe_health(
    *,
    provider: str,
    display_name: str,
    base_url: str,
    env_vars: tuple[str, ...],
) -> AdapterHealth:
    """Adapt the shared cloud-provider readiness check to the adapter contract."""

    from api.providers.cloud.status import check_status

    return AdapterHealth.from_provider_status(
        check_status(
            provider=provider,
            display_name=display_name,
            base_url=base_url,
            env_vars=env_vars,
        )
    )


def _default_turn_starter(session_id: str, message: str, *, source: str, attachments: list[dict[str, Any]] | None = None) -> dict[str, Any]:
    from api.chat_runtime import start_session_turn

    return dict(start_session_turn(session_id, message, source=source, attachments=attachments) or {})


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
        }
        return sorted(mapping[key] for key, enabled in raw.items() if enabled and key in mapping)

    async def stream_chat(self, request, *, session: Any, profile: str | None) -> dict[str, Any]:
        def scoped_health_check() -> AdapterHealth:
            from api.profiles import profile_env_for_active_request_readonly
            from ..request_context import profile_scope

            with profile_scope(profile):
                with profile_env_for_active_request_readonly("adapter health check"):
                    return self.check_health(profile=profile)

        try:
            health = await asyncio.to_thread(scoped_health_check)
        except Exception as exc:
            raise AdapterError(
                503,
                f"{self.display_name} health could not be determined.",
                code="runtime_health_unavailable",
                context={"connection_id": self.adapter_id},
            ) from exc
        if not health.available:
            raise AdapterError(
                400 if self.adapter_id == "jaeger_local" else 503,
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
                attachments=[att.model_dump() for att in request.attachments] if request.attachments else None,
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


class JaegerAdapter(JournaledFrameworkAdapter):
    adapter_id = "jaeger_local"
    display_name = "Jaeger AI"

    def __init__(self, *, turn_starter: TurnStarter | None = None) -> None:
        from api.providers.jaeger.backend import JaegerBackend

        super().__init__(backend=JaegerBackend(), turn_starter=turn_starter)

    def check_health(self, *, profile: str | None) -> AdapterHealth:
        del profile
        # Transport readiness (gateway vs local bridge) is the provider's own
        # concern; this only layers on the Companion requirement, which is an
        # ARES-side prerequisite rather than a JaegerAI one. check_status() is
        # cached, so this stays cheap on the chat-start hot path.
        from api.providers.jaeger.status import check_status

        status = check_status()
        if not status.available:
            return AdapterHealth.from_provider_status(status)

        try:
            from api.providers.jaeger.companion import companion_available

            companion_ready = bool(companion_available())
        except Exception:
            companion_ready = False
        if not companion_ready:
            return AdapterHealth(
                "needs_attention",
                False,
                "Cannot chat: JaegerAI is reachable but no Companion has been "
                "created. Complete onboarding, or choose another provider.",
                dict(status.details),
            )
        return AdapterHealth.from_provider_status(status)

    def get_models(self, *, profile: str | None) -> list[ModelDescriptor]:
        del profile
        health = self.check_health(profile=None)
        model_id = str(health.details.get("model") or "").strip()
        provider = str(health.details.get("provider") or "").strip() or None
        if not model_id:
            return []
        return [ModelDescriptor(model_id, model_id, provider, self.adapter_id)]


class HermesAdapter(JournaledFrameworkAdapter):
    adapter_id = "hermes_local"
    display_name = "Hermes Agent"

    def __init__(self, *, turn_starter: TurnStarter | None = None) -> None:
        from api.providers.hermes.backend import HermesBackend

        super().__init__(backend=HermesBackend(), turn_starter=turn_starter)

    def check_health(self, *, profile: str | None) -> AdapterHealth:
        del profile
        from api.providers.hermes.status import check_status

        return AdapterHealth.from_provider_status(check_status())

    def get_models(self, *, profile: str | None) -> list[ModelDescriptor]:
        del profile
        # Delegate to the backend's real model discovery (Hermes config.yaml + auth.json)
        inventory = self.backend.inventory()
        return _descriptors_from_inventory(inventory, connection_id=self.adapter_id)


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
        # These adapters shell out to a CLI, so an absent binary means the tool
        # was never installed — a different fix from a running-but-down service.
        return AdapterHealth(
            "not_installed",
            False,
            f"{self.display_name} CLI not found on $PATH.",
        )

    def get_models(self, *, profile: str | None) -> list[ModelDescriptor]:
        del profile
        # Delegate to the backend's real model discovery (env/config files)
        inventory = self.backend.inventory()
        return _descriptors_from_inventory(inventory, connection_id=self.adapter_id)


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
        return _provider_probe_health(
            provider="openai",
            display_name=self.display_name,
            base_url="https://api.openai.com/v1",
            env_vars=("OPENAI_API_KEY",),
        )

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
        return _provider_probe_health(
            provider="xai",
            display_name=self.display_name,
            base_url="https://api.x.ai/v1",
            env_vars=("XAI_API_KEY",),
        )

    def get_models(self, *, profile: str | None) -> list[ModelDescriptor]:
        return [ModelDescriptor("grok-3", "Grok 3", "xai", self.adapter_id)]


class GeminiCloudAdapter(JournaledFrameworkAdapter):
    adapter_id = "gemini_cloud"
    display_name = "Google Gemini"

    def __init__(self, *, turn_starter: TurnStarter | None = None) -> None:
        from api.backends.cli_backends import GeminiCloudBackend
        super().__init__(backend=GeminiCloudBackend(), turn_starter=turn_starter)

    def check_health(self, *, profile: str | None) -> AdapterHealth:
        del profile
        from api.providers.cloud.status import check_gemini_status

        return AdapterHealth.from_provider_status(check_gemini_status())

    def get_models(self, *, profile: str | None) -> list[ModelDescriptor]:
        return [
            ModelDescriptor("gemini-2.5-pro", "Gemini 2.5 Pro", "google", self.adapter_id),
            ModelDescriptor("gemini-2.5-flash", "Gemini 2.5 Flash", "google", self.adapter_id),
        ]


class GeminiAntigravityAdapter(JournaledFrameworkAdapter):
    adapter_id = "gemini_antigravity"
    display_name = "Gemini (Antigravity IDE)"

    def __init__(self, *, turn_starter: TurnStarter | None = None) -> None:
        from api.backends.cli_backends import AntigravityGeminiBackend
        super().__init__(backend=AntigravityGeminiBackend(), turn_starter=turn_starter)

    def check_health(self, *, profile: str | None) -> AdapterHealth:
        del profile
        available = self.backend.is_available()
        if available:
            return AdapterHealth(
                "available",
                True,
                "Antigravity IDE is installed. Each action requires explicit consent and macOS automation permission.",
            )
        return AdapterHealth("offline", False, "Antigravity IDE is not installed.")

    def get_models(self, *, profile: str | None) -> list[ModelDescriptor]:
        return [ModelDescriptor("antigravity-default", "Antigravity Active Model", "google", self.adapter_id)]


class OllamaLocalAdapter(JournaledFrameworkAdapter):
    adapter_id = "ollama_local"
    display_name = "Ollama"

    def __init__(self, *, turn_starter: TurnStarter | None = None) -> None:
        from api.backends.cli_backends import OllamaLocalBackend
        super().__init__(backend=OllamaLocalBackend(), turn_starter=turn_starter)

    def check_health(self, *, profile: str | None) -> AdapterHealth:
        del profile
        from api.providers.ollama.status import check_status

        return AdapterHealth.from_provider_status(check_status())

    def get_models(self, *, profile: str | None) -> list[ModelDescriptor]:
        del profile
        # Delegate to the backend's real model discovery via inventory()
        # This ensures Registry A and Registry B report the same models
        inventory = self.backend.inventory()
        return _descriptors_from_inventory(inventory, connection_id=self.adapter_id)
