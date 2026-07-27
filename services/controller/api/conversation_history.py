"""Format conversation history for injection into backend prompts.

LangGraph-style: the orchestrator owns the history, not the model.
Every backend receives the full message history formatted as context,
so switching backends preserves continuity.

This is the single source of truth for history formatting. All backends
use it. No backend should reconstruct history on its own.
"""

from __future__ import annotations

import logging
from typing import Any

logger = logging.getLogger(__name__)

# ── Helpers ──────────────────────────────────────────────────────────────

def _backend_label(backend_id: str | None) -> str:
    """Map a backend id to a human-readable label for handoff messages."""
    if not backend_id:
        return "unknown"
    labels = {
        "hermes_local": "Hermes Agent",
        "jros_local": "Jaeger AI (JROS)",
        "claude_local": "Claude Code",
        "codex_local": "OpenAI Codex",
        "gemini_local": "Gemini",
        "grok_local": "Grok",
        "opencode_local": "OpenCode",
        "cursor_local": "Cursor",
        "pi_local": "Pi",
        "ollama_local": "Ollama (local)",
        "ollama_cloud": "Ollama Cloud",
        "openai_cloud": "OpenAI",
        "xai_cloud": "xAI",
        "hatchery": "Hatchery",
    }
    return labels.get(backend_id, backend_id)


def _get_backend_for_message(msg: dict) -> str | None:
    """Extract the backend id from a message's metadata, if stored."""
    return str(msg.get("backend_id") or msg.get("worker") or "").strip() or None


def detect_handoff(
    messages: list[dict],
    current_backend_id: str | None,
) -> tuple[str | None, str | None]:
    """Detect if the backend changed since the last assistant message.

    Returns (handoff_from, handoff_to) or (None, None) if no change.
    """
    if not current_backend_id:
        return None, None
    # Walk backwards to find the last assistant message with a backend id
    for msg in reversed(messages):
        if msg.get("role") == "assistant":
            prev = _get_backend_for_message(msg)
            if prev and prev != current_backend_id:
                return prev, current_backend_id
            break
    return None, None


def format_conversation_history(
    messages: list[dict],
    *,
    handoff_from: str | None = None,
    handoff_to: str | None = None,
    max_chars: int = 12000,
) -> str:
    """Format previous messages into a context string for the backend.

    Includes a handoff marker when the backend changed between turns.
    The last user message (the current turn) is excluded — it will be
    sent separately as the active message.

    Args:
        messages: Full session message list (user + assistant turns).
        handoff_from: Previous backend id (if a handoff occurred).
        handoff_to: Current backend id (if a handoff occurred).
        max_chars: Rough character limit for the formatted history.

    Returns:
        A formatted string to inject into the backend's prompt context.
    """
    parts: list[str] = []

    # 1. Handoff marker
    if handoff_from and handoff_to and handoff_from != handoff_to:
        from_label = _backend_label(handoff_from)
        to_label = _backend_label(handoff_to)
        parts.append(
            f"[Handoff: conversation continued from {from_label} to {to_label}. "
            f"Maintain the same context, persona, and conclusions reached so far.]"
        )

    # 2. Build history (exclude the last user message — that's the current turn)
    history = list(messages)
    if history and history[-1].get("role") == "user":
        history = history[:-1]

    if not history:
        return "\n".join(parts)

    # 3. Format each message
    formatted: list[str] = []
    char_count = sum(len(p) for p in parts)

    for msg in history:
        role = str(msg.get("role", "unknown")).strip()
        content = str(msg.get("content", "")).strip()
        if not content:
            continue

        # Truncate individual messages that are too long
        if len(content) > 4000:
            content = content[:2000] + "\n...[truncated]...\n" + content[-2000:]

        line = f"{role}: {content}"
        char_count += len(line) + 1

        if char_count > max_chars:
            formatted.append("...[conversation history truncated]...")
            break

        formatted.append(line)

    if not formatted:
        return "\n".join(parts)

    parts.append("")
    parts.append("--- Previous conversation ---")
    parts.extend(formatted)
    parts.append("--- End of previous conversation ---")
    parts.append("")

    return "\n".join(parts)


def build_context_prompt(
    message: str,
    messages: list[dict],
    *,
    current_backend_id: str | None = None,
    max_chars: int = 12000,
) -> str:
    """Build the full prompt for a backend turn.

    Combines conversation history (with handoff detection) + the current message.

    This is the main entry point for backends. Call this instead of
    format_conversation_history() when you want the complete prompt.
    """
    handoff_from, handoff_to = detect_handoff(messages, current_backend_id)
    history = format_conversation_history(
        messages,
        handoff_from=handoff_from,
        handoff_to=handoff_to,
        max_chars=max_chars,
    )

    if history.strip():
        return f"{history}\n\n{message}"
    return message
