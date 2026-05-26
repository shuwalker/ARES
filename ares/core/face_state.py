"""ARES face state machine — maps cognition to expression.

6 states, each with visual parameters for color, opacity, pulse speed, pupil offset.
Directly usable by both Python cognition layer and SwiftUI FaceRenderer.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum
from typing import Tuple


class FaceState(Enum):
    """Emotional/operational states for the companion face."""

    IDLE = "idle"  # Waiting, ambient awareness
    AWAKENED = "awakened"  # Wake word detected, attention focused
    LISTENING = "listening"  # Processing speech input
    THINKING = "thinking"  # LLM inference in progress
    SPEAKING = "speaking"  # TTS output, mouth animation
    SLEEPING = "sleeping"  # Dormant / low-power


@dataclass(frozen=True)
class FaceConfig:
    """Visual parameters for a face state."""

    color: Tuple[float, float, float]  # RGB 0-1
    opacity: float  # 0-1
    pulse_speed: float  # animation cycles/sec
    pulse_amount: float  # 0-1 intensity
    pupil_offset: Tuple[float, float]  # x,y offset from center (-1 to 1)


STATE_CONFIGS: dict[FaceState, FaceConfig] = {
    FaceState.IDLE: FaceConfig(
        color=(0.6, 0.6, 0.7), opacity=0.6, pulse_speed=0.3, pulse_amount=0.1, pupil_offset=(0.0, 0.0)
    ),
    FaceState.AWAKENED: FaceConfig(
        color=(0.4, 0.7, 1.0), opacity=0.9, pulse_speed=1.5, pulse_amount=0.2, pupil_offset=(0.0, -0.1)
    ),
    FaceState.LISTENING: FaceConfig(
        color=(0.3, 0.9, 0.5), opacity=1.0, pulse_speed=2.0, pulse_amount=0.3, pupil_offset=(0.05, 0.05)
    ),
    FaceState.THINKING: FaceConfig(
        color=(0.9, 0.6, 0.2), opacity=1.0, pulse_speed=3.0, pulse_amount=0.4, pupil_offset=(0.0, 0.2)
    ),
    FaceState.SPEAKING: FaceConfig(
        color=(0.5, 0.8, 1.0), opacity=1.0, pulse_speed=0.5, pulse_amount=0.05, pupil_offset=(0.0, -0.05)
    ),
    FaceState.SLEEPING: FaceConfig(
        color=(0.2, 0.2, 0.3), opacity=0.3, pulse_speed=0.1, pulse_amount=0.05, pupil_offset=(0.0, 0.1)
    ),
}


def get_face_config(state: FaceState) -> FaceConfig:
    """Get visual config for a face state."""
    return STATE_CONFIGS[state]


def emotion_to_face_state(emotion: str, is_processing: bool = False) -> FaceState:
    """Map a high-level emotion string to a face state.

    Called by the cognition layer when ARES determines what to express.
    """
    if emotion in ("happy", "excited", "enthusiastic"):
        return FaceState.AWAKENED
    elif emotion in ("sad", "disappointed", "concerned"):
        return FaceState.IDLE
    elif emotion in ("thinking", "analyzing", "computing"):
        return FaceState.THINKING
    elif emotion in ("surprised", "curious", "interested"):
        return FaceState.LISTENING
    elif emotion in ("neutral", "calm", "focused"):
        return FaceState.IDLE

    return FaceState.THINKING if is_processing else FaceState.IDLE
