"""ARES cognitive core — Layer 1. Portable, no body assumption, no platform imports.

Modules:
    identity    — Who ARES is (name, role, voice, self-model)
    personality — 4-layer personality (HEXACO, SPECIAL, Expression, Domains)
    face_state  — Face state machine (6 states with RGB, opacity, pulse, pupils)
    bus         — ZMQ pub/sub backbone (nervous system connecting all modules)
    memory      — Persistent fact storage (SQLite)
    agent       — Swappable brain interface (AgentInterface + backends)
"""

from ares.core.identity import Identity, DEFAULT_IDENTITY
from ares.core.personality import CharacterProfile, DEFAULT_PROFILE
from ares.core.face_state import FaceState, FaceConfig, get_face_config
from ares.core.bus import ARESBus, BusMessage, PortMap, get_bus
