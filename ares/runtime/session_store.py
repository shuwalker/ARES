"""Volatile per-session turn history.

Process-lifetime only — restarting the daemon clears it. Persistent
memory lives in `memory_store.MemoryStore`.
"""

from __future__ import annotations

from collections import defaultdict, deque
from dataclasses import dataclass, field
from typing import Deque, Iterable


@dataclass
class Turn:
    role: str  # "user" | "assistant"
    text: str
    timestamp: float

    def to_dict(self) -> dict:
        return {"role": self.role, "text": self.text, "timestamp": self.timestamp}


class SessionStore:
    """In-memory ring buffer of recent turns, keyed by session id."""

    def __init__(self, capacity: int = 12):
        self.capacity = capacity
        self._sessions: dict[str, Deque[Turn]] = defaultdict(
            lambda: deque(maxlen=capacity)
        )

    def record(self, session_id: str, role: str, text: str, timestamp: float) -> None:
        if not session_id:
            return
        self._sessions[session_id].append(
            Turn(role=role, text=text, timestamp=timestamp)
        )

    def history(self, session_id: str) -> list[Turn]:
        return list(self._sessions.get(session_id, ()))

    def session_ids(self) -> list[str]:
        return list(self._sessions.keys())

    def clear(self, session_id: str) -> None:
        self._sessions.pop(session_id, None)

    def reset(self) -> None:
        self._sessions.clear()
