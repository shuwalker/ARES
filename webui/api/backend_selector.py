"""ARES Backend Selector — routes agent execution to any registered backend.

Paperclip pattern: flat registry, agnostic naming. Each backend is
{name}_{deployment}. No roles, no opinions. The UI iterates the map.
"""
from __future__ import annotations

import logging
from typing import Optional

from .backends.router import get_router

logger = logging.getLogger(__name__)

VALID_BACKENDS = (
    "hermes_local", "jros_local",
    "claude_local", "codex_local", "gemini_local", "grok_local",
    "opencode_local", "cursor_local", "pi_local",
    "openai_cloud", "xai_cloud", "ollama_local",
)


def normalize_backend(value: object, *, fallback: str = "hermes_local") -> str:
    raw = str(value or "").strip().lower()
    if raw in VALID_BACKENDS:
        return raw
    return fallback if fallback in VALID_BACKENDS else "hermes_local"


def get_active_backend(config: dict) -> str:
    return normalize_backend((config or {}).get("ares_backend", ""))


def get_session_backend(session: object, config: dict) -> str:
    default_backend = get_active_backend(config)
    return normalize_backend(getattr(session, "ares_backend", None), fallback=default_backend)


def backend_status() -> dict:
    """Return current backend availability for UI display."""
    router = get_router()
    status = {}
    for name, backend in router.list_all().items():
        status[name] = backend.is_available()
    return status


def backend_label(backend: str) -> str:
    """Human-readable label for the backend selector dropdown."""
    labels = {
        "hermes_local": "Hermes Agent",
        "jros_local": "JROS",
        "claude_local": "Claude Code",
        "codex_local": "OpenAI Codex",
        "gemini_local": "Google Gemini",
        "grok_local": "xAI Grok",
        "opencode_local": "OpenCode",
        "cursor_local": "Cursor",
        "pi_local": "Pi Coding Agent",
        "openai_cloud": "OpenAI",
        "xai_cloud": "xAI Grok",
        "ollama_local": "Ollama",
    }
    return labels.get(backend, backend)
