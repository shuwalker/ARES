"""ARES Backend Router — flat registry of agnostic backends.

Paperclip pattern: every adapter is just {name}_{deployment}.
No roles, no opinions. The UI iterates the map.
"""
from __future__ import annotations

from typing import Any, Dict

from .base import AgenticBackend
from .hermes import HermesBackend
from .jros import JROSBackend
from .cli_backends import (
    ClaudeLocalBackend,
    CodexLocalBackend,
    CursorLocalBackend,
    GeminiLocalBackend,
    GrokLocalBackend,
    OllamaLocalBackend,
    OpenAICloudBackend,
    OpenCodeLocalBackend,
    PiLocalBackend,
    XAICloudBackend,
)


def get_default_router() -> BackendRouter:
    """Factory returning the canonical ARES router with all available backends."""
    backends: Dict[str, AgenticBackend] = {
        "hermes_local": HermesBackend(),
        "jros_local": JROSBackend(),
        "claude_local": ClaudeLocalBackend(),
        "codex_local": CodexLocalBackend(),
        "gemini_local": GeminiLocalBackend(),
        "grok_local": GrokLocalBackend(),
        "opencode_local": OpenCodeLocalBackend(),
        "cursor_local": CursorLocalBackend(),
        "pi_local": PiLocalBackend(),
        "openai_cloud": OpenAICloudBackend(),
        "xai_cloud": XAICloudBackend(),
        "ollama_local": OllamaLocalBackend(),
    }
    return BackendRouter(backends)


_router: BackendRouter | None = None


def get_router() -> BackendRouter:
    global _router
    if _router is None:
        _router = get_default_router()
    return _router


class BackendRouter:
    """Flat registry of backends. Paperclip pattern — iterate the map."""

    def __init__(self, backends: Dict[str, AgenticBackend]):
        self.backends = backends

    def select(self, requested: str) -> AgenticBackend | None:
        backend = self.backends.get(requested)
        if backend and backend.is_available():
            return backend
        return None

    def select_worker(self, requested: str) -> tuple:
        backend = self.backends.get(requested)
        if backend and backend.is_available():
            return backend.get_worker_target()
        # Fallback: first available
        for b in self.backends.values():
            if b.is_available():
                return b.get_worker_target()
        return list(self.backends.values())[0].get_worker_target()

    def register(self, name: str, backend: AgenticBackend) -> None:
        """Register a new backend at runtime (plugin pattern)."""
        self.backends[name] = backend

    def unregister(self, name: str) -> None:
        self.backends.pop(name, None)

    def list_available(self) -> Dict[str, AgenticBackend]:
        return {k: v for k, v in self.backends.items() if v.is_available()}

    def list_all(self) -> Dict[str, AgenticBackend]:
        return dict(self.backends)
