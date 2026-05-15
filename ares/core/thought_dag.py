"""ThoughtDAG — checkpoint reasoning cycles to SQLite.

Every major step of a reasoning call (``reason()`` in ``ares.reasoning``)
writes a ``ThoughtCheckpoint`` row linked via ``parent_id`` to its
predecessor. The resulting graph supports:

  * Crash recovery — if ARES dies mid-reasoning, the daemon can resume
    from the last completed ``parsed`` checkpoint instead of re-running
    the LLM call.
  * Time-travel debugging — walk back the chain to inspect inputs and
    outputs of any past stage for any task.

Storage: ``~/.ares/thoughts.db``. One SQLite file. Reads and writes are
serialized with an in-process lock; SQLite's own locking covers the
multi-process case if any other tool ever reads the file.
"""

from __future__ import annotations

import json
import sqlite3
import threading
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from pydantic import BaseModel, ConfigDict, Field

from ares.runtime.config import ares_paths


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def new_thought_id() -> str:
    return f"thought-{uuid.uuid4().hex[:12]}"


# ---------------------------------------------------------------------------
# Pydantic schema
# ---------------------------------------------------------------------------

class ThoughtCheckpoint(BaseModel):
    """A single checkpoint in a reasoning DAG."""

    model_config = ConfigDict(validate_assignment=False)

    thought_id: str = Field(default_factory=new_thought_id, description="Unique checkpoint identifier")
    parent_id: str | None = Field(default=None, description="Predecessor checkpoint id (None for root)")
    task_id: str | None = Field(default=None, description="ARES task id this thought belongs to")
    stage: str = Field(description="Reasoning stage name — e.g. 'started', 'llm_request', 'parsed', 'done'")
    status: str = Field(default="done", description="done | running | failed")
    inputs: dict[str, Any] = Field(default_factory=dict, description="State entering this stage")
    outputs: dict[str, Any] = Field(default_factory=dict, description="State leaving this stage")
    error: str = Field(default="", description="Error message when status == 'failed'")
    timestamp: str = Field(default_factory=_now_iso, description="ISO-8601 UTC checkpoint time")


# ---------------------------------------------------------------------------
# SQLite store
# ---------------------------------------------------------------------------

_SCHEMA = """
CREATE TABLE IF NOT EXISTS thoughts (
    thought_id TEXT PRIMARY KEY,
    parent_id  TEXT,
    task_id    TEXT,
    stage      TEXT NOT NULL,
    status     TEXT NOT NULL DEFAULT 'done',
    inputs     TEXT NOT NULL DEFAULT '{}',
    outputs    TEXT NOT NULL DEFAULT '{}',
    error      TEXT NOT NULL DEFAULT '',
    timestamp  TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_thoughts_task_id   ON thoughts(task_id);
CREATE INDEX IF NOT EXISTS idx_thoughts_parent_id ON thoughts(parent_id);
CREATE INDEX IF NOT EXISTS idx_thoughts_timestamp ON thoughts(timestamp);
"""


class ThoughtDAG:
    """SQLite-backed checkpoint store. Thread-safe within a process."""

    def __init__(self, db_path: Path | None = None) -> None:
        if db_path is None:
            db_path = ares_paths()["home"] / "thoughts.db"
        self.db_path = Path(db_path)
        self._lock = threading.Lock()
        self._ensure_schema()

    # -- internals -----------------------------------------------------------

    def _connect(self) -> sqlite3.Connection:
        conn = sqlite3.connect(str(self.db_path))
        conn.row_factory = sqlite3.Row
        return conn

    def _ensure_schema(self) -> None:
        with self._lock, self._connect() as conn:
            conn.executescript(_SCHEMA)

    @staticmethod
    def _row_to_checkpoint(row: sqlite3.Row) -> ThoughtCheckpoint:
        return ThoughtCheckpoint(
            thought_id=row["thought_id"],
            parent_id=row["parent_id"],
            task_id=row["task_id"],
            stage=row["stage"],
            status=row["status"],
            inputs=json.loads(row["inputs"] or "{}"),
            outputs=json.loads(row["outputs"] or "{}"),
            error=row["error"] or "",
            timestamp=row["timestamp"],
        )

    # -- public API ----------------------------------------------------------

    def record(self, cp: ThoughtCheckpoint) -> None:
        """Insert or replace a checkpoint by thought_id."""
        with self._lock, self._connect() as conn:
            conn.execute(
                "INSERT OR REPLACE INTO thoughts "
                "(thought_id, parent_id, task_id, stage, status, inputs, outputs, error, timestamp) "
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                (
                    cp.thought_id,
                    cp.parent_id,
                    cp.task_id,
                    cp.stage,
                    cp.status,
                    json.dumps(cp.inputs, default=str),
                    json.dumps(cp.outputs, default=str),
                    cp.error,
                    cp.timestamp,
                ),
            )

    def get(self, thought_id: str) -> ThoughtCheckpoint | None:
        with self._lock, self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM thoughts WHERE thought_id = ?",
                (thought_id,),
            ).fetchone()
            return self._row_to_checkpoint(row) if row else None

    def chain(self, thought_id: str) -> list[ThoughtCheckpoint]:
        """Walk parent_id from ``thought_id`` back to root. Oldest → newest."""
        thoughts: list[ThoughtCheckpoint] = []
        current: str | None = thought_id
        seen: set[str] = set()
        while current and current not in seen:
            seen.add(current)
            cp = self.get(current)
            if cp is None:
                break
            thoughts.append(cp)
            current = cp.parent_id
        return list(reversed(thoughts))

    def for_task(self, task_id: str) -> list[ThoughtCheckpoint]:
        """All checkpoints for a task, oldest-first."""
        with self._lock, self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM thoughts WHERE task_id = ? ORDER BY timestamp ASC",
                (task_id,),
            ).fetchall()
            return [self._row_to_checkpoint(r) for r in rows]

    def latest_for_task(self, task_id: str) -> ThoughtCheckpoint | None:
        cps = self.for_task(task_id)
        return cps[-1] if cps else None

    def find_completed_plan(self, task_id: str) -> dict[str, Any] | None:
        """Return the cached plan dict from the most recent successful 'parsed' checkpoint.

        Used by ``reasoning.reason()`` to short-circuit after a crash: if a
        plan was successfully parsed for this task in a previous run, skip
        the LLM call and re-use it.
        """
        for cp in reversed(self.for_task(task_id)):
            if cp.stage == "parsed" and cp.status == "done":
                plan_data = cp.outputs.get("plan")
                if isinstance(plan_data, dict) and plan_data:
                    return plan_data
        return None

    def list_recent(self, limit: int = 50) -> list[ThoughtCheckpoint]:
        with self._lock, self._connect() as conn:
            rows = conn.execute(
                "SELECT * FROM thoughts ORDER BY timestamp DESC LIMIT ?",
                (limit,),
            ).fetchall()
            return [self._row_to_checkpoint(r) for r in rows]


# ---------------------------------------------------------------------------
# Singleton accessor
# ---------------------------------------------------------------------------

_DAG: ThoughtDAG | None = None
_DAG_LOCK = threading.Lock()


def get_dag() -> ThoughtDAG:
    global _DAG
    with _DAG_LOCK:
        if _DAG is None:
            _DAG = ThoughtDAG()
    return _DAG
