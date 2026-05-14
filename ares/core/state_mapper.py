"""State mapper — translate agent events and control tags into face states.

This is the bridge between whatever brain is active (Hermes, Lilith, local)
and the ARES face rendering. Every backend produces the same set of events,
and this module maps them to the face_state machine's states and expressions.

Priority order: control tags > agent events > sentiment fallback.
"""

from __future__ import annotations

from ares.core.face_state import FaceState

# Agent event → (face_state, expression)
AGENT_TO_FACE: dict[str, tuple[str, str]] = {
    "thinking":           ("thinking", "thinking"),
    "tool_call":          ("curious", "curious"),
    "tool_executing":     ("curious", "curious"),
    "streaming":          ("speaking", "neutral"),
    "idle":               ("idle", "neutral"),
    "error":              ("error", "concerned"),
    "perceiving":         ("awakened", "curious"),
    "listening":          ("listening", "neutral"),
    "awakened":          ("awakened", "surprised"),
    "sleeping":          ("sleeping", "sleepy"),
}

# Control tag patterns → (face_state, expression)
CONTROL_TAG_MAP: dict[str, tuple[str, str]] = {
    "face:happy":         ("speaking", "happy"),
    "face:curious":      ("listening", "curious"),
    "face:thinking":     ("thinking", "thinking"),
    "face:surprised":    ("awakened", "surprised"),
    "face:concerned":    ("listening", "concerned"),
    "face:excited":      ("speaking", "excited"),
    "face:sleepy":       ("idle", "sleepy"),
    "face:neutral":      ("idle", "neutral"),
    "anim:wave":         ("speaking", "happy"),
    "anim:look":         ("awakened", "curious"),
    "anim:nod":          ("speaking", "neutral"),
    "anim:shake":        ("listening", "concerned"),
}


def map_agent_state(event: str, text: str = "") -> tuple[str, str]:
    """Map an agent event + response text to (face_state, expression).

    Priority: control tags > agent events > sentiment fallback.
    """
    # 1. Check control tags in text
    for tag, state_expr in CONTROL_TAG_MAP.items():
        if f"[{tag}]" in text:
            return state_expr

    # 2. Check agent events
    if event in AGENT_TO_FACE:
        return AGENT_TO_FACE[event]

    # 3. Fallback
    return ("idle", "neutral")


def validate_face_state(state_str: str) -> FaceState | None:
    """Convert a string to FaceState, returning None if invalid."""
    try:
        return FaceState(state_str)
    except ValueError:
        return None