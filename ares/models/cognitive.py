"""Cognitive snapshot models — the transport contract between ARES's
cognitive loop and any UI / API consumer.

Schema versioning: consumers must treat unknown fields as forward-compatible
additions and ignore them. Adding a field is non-breaking. Removing or
renaming one bumps `SCHEMA_VERSION`.
"""

from __future__ import annotations

import time
from typing import Optional

from pydantic import BaseModel, Field

SCHEMA_VERSION = 1


class LoopBlock(BaseModel):
    """Snapshot of the loop's tick state."""

    cycle: int = 0
    phase: str = "idle"
    urgency: str = "low"
    budget_remaining: float = 1.0
    tokens_used: int = 0
    elapsed_ms: int = 0


class ThoughtNode(BaseModel):
    """A single node in the reasoning DAG.

    Nodes form a DAG (not a tree) — `parent_ids` may have multiple entries
    when a step has multiple inputs (e.g. tool output + retrieved memory).
    """

    id: str
    parent_ids: list[str] = Field(default_factory=list)
    label: str
    status: str = "pending"  # "pending" | "running" | "done" | "failed"
    duration_ms: int = 0
    evidence: list[dict] = Field(default_factory=list)


class ThoughtBlock(BaseModel):
    """Snapshot of the current reasoning step.

    Nullable in `CognitiveSnapshot.thought` while the loop is idle. Fields
    here are populated incrementally as ARES gains the ability to measure
    them — for v1 `summary` and `branches` are wired.
    """

    summary: Optional[str] = None
    depth: int = 0
    confidence: Optional[float] = None
    sentiment: Optional[float] = None
    branches: list[ThoughtNode] = Field(default_factory=list)


class MemoryHitBlock(BaseModel):
    """A single memory hit surfaced to the UI."""

    id: str
    score: float
    text: str
    kind: str = "episodic"


class CognitiveSnapshot(BaseModel):
    """Versioned snapshot of ARES's cognitive state.

    Served by `GET /api/cognitive/status` and pushed over the
    `/ws` WebSocket as `{"type": "cognitive_snapshot", ...}` on every
    phase transition.
    """

    schema_version: int = Field(default=SCHEMA_VERSION)
    timestamp: float = Field(default_factory=time.time)
    running: bool = False
    loop: LoopBlock = Field(default_factory=LoopBlock)
    thought: Optional[ThoughtBlock] = None
    memory_recall: list[MemoryHitBlock] = Field(default_factory=list)
    errors: list[str] = Field(default_factory=list)
