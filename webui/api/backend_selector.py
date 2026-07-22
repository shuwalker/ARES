"""ARES Backend Selector — routes agent execution to any registered backend.

Paperclip pattern: flat registry, agnostic naming. Each backend is
{name}_{deployment}. No roles, no opinions. The UI iterates the map.
"""
from __future__ import annotations

import logging
import time
from typing import Optional

from .backends.router import get_router

logger = logging.getLogger(__name__)

BACKEND_JROS = "jros_local"

VALID_BACKENDS = (
    "hermes_local", "jros_local",
    "claude_local", "codex_local", "gemini_local", "grok_local",
    "opencode_local", "cursor_local", "pi_local",
    "openai_cloud", "xai_cloud", "gemini_cloud", "gemini_antigravity",
    "ollama_local",
)

_BACKEND_ALIASES = {
    "hermes": "hermes_local",
    "jaeger": "jros_local",
    "jros": "jros_local",
}

_jros_available_cache: Optional[bool] = None
_jros_available_ts = 0.0
_jros_gateway_info: dict = {}
_JROS_CACHE_TTL = 5.0


def normalize_backend(value: object, *, fallback: str = "") -> str:
    raw_value = str(value or "").strip().lower()
    raw = _BACKEND_ALIASES.get(raw_value, raw_value)
    if raw in VALID_BACKENDS:
        return raw
    return fallback if fallback in VALID_BACKENDS else ""


def get_active_backend(config: dict) -> str:
    """Return the explicitly elected external runtime, or an empty string."""
    return normalize_backend((config or {}).get("ares_backend", ""))


def get_session_backend(session: object, config: dict) -> str:
    default_backend = get_active_backend(config)
    return normalize_backend(getattr(session, "ares_backend", None), fallback=default_backend)


def is_jros_available() -> bool:
    """Bounded, cached JaegerAI *execution* probe shared by every adapter surface.

    A local checkout alone is install-detected, not available. Availability
    requires a live gateway health response so readiness cannot claim
    execution is ready from disk presence alone.
    """

    global _jros_available_cache, _jros_available_ts, _jros_gateway_info
    now = time.monotonic()
    if _jros_available_cache is not None and now - _jros_available_ts < _JROS_CACHE_TTL:
        return _jros_available_cache

    available = False
    details: dict = {}
    try:
        from api.jros_gateway_chat import jros_gateway_health

        reply = jros_gateway_health(timeout=1.0)
        if reply is not None:
            available = True
            details = {
                "mode": "gateway",
                "model": reply.get("model"),
                "provider": reply.get("provider"),
                "booted": bool(reply.get("booted")),
                "instance": reply.get("instance"),
            }
    except Exception:
        logger.debug("JaegerAI availability probe failed", exc_info=True)

    _jros_available_cache = available
    _jros_available_ts = now
    _jros_gateway_info = details
    return available


def jros_gateway_details() -> dict:
    """Cached gateway details from the last successful :func:`is_jros_available` probe."""

    # Refresh cache if empty/stale so health surfaces stay current.
    is_jros_available()
    return dict(_jros_gateway_info or {})


def backend_status() -> dict:
    """Return current backend availability for UI display.

    Note: this probes *every* registered backend and is intentionally not used
    on the chat start hot path (use :func:`is_jros_available` /
    per-backend ``is_available`` instead).
    """
    router = get_router()
    status = {
        name: backend.is_available()
        for name, backend in router.list_all().items()
        if name not in {"jros", "jros_local"}
    }
    jros_available = is_jros_available()
    status["jros_local"] = jros_available
    if jros_available and _jros_gateway_info:
        for key, value in _jros_gateway_info.items():
            status[f"jros_{key}"] = value
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
        "gemini_cloud": "Google Gemini API",
        "gemini_antigravity": "Gemini (Antigravity IDE)",
        "ollama_local": "Ollama",
    }
    return labels.get(backend, backend)
