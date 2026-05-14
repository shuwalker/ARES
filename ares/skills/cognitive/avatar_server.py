"""
ARES Avatar MCP Server — Live2D anime avatar control for Hermes.

Exposes VTube Studio avatar control as MCP tools so Hermes agent
can express emotions, speak, and follow gaze naturally.

MCP server :9514, StreamableHTTP.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Add ARES-App source to path
APP_SRC = Path(__file__).resolve().parent.parent.parent.parent
sys.path.insert(0, str(APP_SRC))

from mcp.server.fastmcp import FastMCP  # noqa: E402 — must follow sys.path.insert above

server = FastMCP(
    name="ARES Avatar",
    instructions="Live2D anime avatar control via VTube Studio. AI-driven expressions, lip sync, gaze tracking.",
    host="0.0.0.0",
    port=9514,
)

# ── Helpers ──────────────────────────────────────────────────────────────


def _get_vts():
    try:
        from ares.skills.cognitive.vts_controller import (
            get_controller,
            connect_avatar,
            set_expression as vts_set_expr,
            speak_animation as vts_speak,
            look_at as vts_look,
            avatar_connected,
            AvatarExpression,
        )

        return get_controller, connect_avatar, vts_set_expr, vts_speak, vts_look, avatar_connected, AvatarExpression
    except ImportError:
        return None, None, None, None, None, None, None


# ── Tools ─────────────────────────────────────────────────────────────────


@server.tool()
def avatar_connect() -> dict:
    """Connect to VTube Studio and start the Live2D avatar.

    VTube Studio must be running (Steam → VTube Studio).
    This starts the AI-driven expression + blink animation loop at 30fps.

    Returns:
        dict: connection status
    """
    _, connect, _, _, _, connected_fn, _ = _get_vts()
    if connect is None:
        return {"status": "error", "error": "VTS controller not available — install pyvts"}

    if connected_fn and connected_fn():
        return {"status": "ok", "message": "Avatar already connected"}

    ok = connect()
    if ok:
        return {"status": "ok", "message": "Avatar connected — AI expressions live"}
    else:
        return {
            "status": "error",
            "message": "VTube Studio not running. Start VTube Studio on Steam, enable API (Settings → check 'Allow API access').",
        }


@server.tool()
def avatar_expression(emotion: str = "neutral") -> dict:
    """Set the avatar's facial expression.

    The AI cognition layer calls this based on conversation context.
    Transitions smoothly over ~300ms.

    Args:
        emotion: One of neutral, happy, curious, thinking, surprised, concerned, excited, sleepy

    Returns:
        dict: new expression state
    """
    _, _, set_expr, _, _, _, AvatarExpression = _get_vts()
    if set_expr is None:
        return {"status": "error", "error": "VTS not available"}

    valid = {
        "neutral",
        "happy",
        "curious",
        "thinking",
        "surprised",
        "concerned",
        "excited",
        "sleepy",
    }
    emotion = emotion.lower()
    if emotion not in valid:
        emotion = "neutral"

    try:
        expr = AvatarExpression(emotion)
    except (ValueError, TypeError):
        expr = AvatarExpression.NEUTRAL

    set_expr(expr)
    return {"status": "ok", "expression": emotion}


@server.tool()
def avatar_speak(audio_level: float = 0.5) -> dict:
    """Animate the avatar's mouth for speaking.

    Call this WHILE speaking to sync lip movement with TTS audio.
    audio_level should fluctuate with the audio waveform amplitude.

    Args:
        audio_level: Mouth openness 0.0 (closed) to 1.0 (wide open)

    Returns:
        dict: current mouth state
    """
    _, _, _, speak_fn, _, _, _ = _get_vts()
    if speak_fn is None:
        return {"status": "error"}

    level = max(0.0, min(1.0, audio_level))
    speak_fn(level)
    return {"status": "ok", "mouth_open": level}


@server.tool()
def avatar_look_at(x: float = 0.0, y: float = 0.0) -> dict:
    """Make the avatar look at a point on screen.

    Used for gaze following — camera tracks person → map position → avatar eyes follow.

    Args:
        x: Horizontal gaze -1.0 (far left) to 1.0 (far right)
        y: Vertical gaze -1.0 (down) to 1.0 (up)

    Returns:
        dict: gaze state
    """
    _, _, _, _, look_fn, _, _ = _get_vts()
    if look_fn is None:
        return {"status": "error"}

    x = max(-1.0, min(1.0, x))
    y = max(-1.0, min(1.0, y))
    look_fn(x, y)
    return {"status": "ok", "gaze_x": x, "gaze_y": y}


@server.tool()
def avatar_state() -> dict:
    """Get current avatar state: connection status, expression, gaze.

    Returns:
        dict: full avatar status
    """
    _, _, _, _, _, connected_fn, _ = _get_vts()

    connected = connected_fn() if connected_fn else False
    return {
        "status": "ok",
        "connected": connected,
        "runtime": "VTube Studio + Live2D",
        "available": connected_fn is not None,
    }


if __name__ == "__main__":
    server.run(transport="streamable-http")
