"""Canonical backend identities and compatibility aliases.

Product names, persisted IDs, and transport-era aliases are deliberately kept
separate here. New state is always written with the canonical ID; old state is
accepted at the boundary and normalized before it reaches application logic.
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class BackendDefinition:
    id: str
    label: str


JAEGER_BACKEND_ID = "jaeger_local"

BACKENDS: tuple[BackendDefinition, ...] = (
    BackendDefinition("hermes_local", "Hermes Agent"),
    BackendDefinition(JAEGER_BACKEND_ID, "Jaeger AI"),
    BackendDefinition("claude_local", "Claude Code"),
    BackendDefinition("codex_local", "OpenAI Codex"),
    BackendDefinition("gemini_local", "Google Gemini"),
    BackendDefinition("grok_local", "xAI Grok"),
    BackendDefinition("opencode_local", "OpenCode"),
    BackendDefinition("cursor_local", "Cursor"),
    BackendDefinition("pi_local", "Pi Coding Agent"),
    BackendDefinition("openai_cloud", "OpenAI"),
    BackendDefinition("xai_cloud", "xAI Grok"),
    BackendDefinition("gemini_cloud", "Google Gemini API"),
    BackendDefinition("gemini_antigravity", "Gemini (Antigravity IDE)"),
    BackendDefinition("ollama_local", "Ollama"),
)

BACKEND_BY_ID = {backend.id: backend for backend in BACKENDS}
VALID_BACKEND_IDS = tuple(BACKEND_BY_ID)

# Read-only migration boundary. Never expose or persist these values as the
# selected backend after normalization.
BACKEND_ALIASES = {
    "hermes": "hermes_local",
    "jaeger": JAEGER_BACKEND_ID,
    "jaegerai": JAEGER_BACKEND_ID,
    "jaeger_ai": JAEGER_BACKEND_ID,
    "jros": JAEGER_BACKEND_ID,
    "jros_local": JAEGER_BACKEND_ID,
}


def normalize_backend_id(value: object, *, fallback: str = "") -> str:
    raw = str(value or "").strip().lower()
    normalized = BACKEND_ALIASES.get(raw, raw)
    if normalized in BACKEND_BY_ID:
        return normalized
    normalized_fallback = BACKEND_ALIASES.get(str(fallback or "").strip().lower(), fallback)
    return normalized_fallback if normalized_fallback in BACKEND_BY_ID else ""


def backend_display_name(value: object) -> str:
    normalized = normalize_backend_id(value)
    if not normalized:
        return str(value or "")
    return BACKEND_BY_ID[normalized].label
