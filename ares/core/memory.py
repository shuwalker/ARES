"""ARES unified memory — SQLite + WAL, shared across main agent and all subagents.

Three-tier persistence:
1. SQLite (fast ops, facts, sessions, outcomes) — this module
2. Obsidian vault (canonical knowledge, reports, research) — NAS path
3. twin_state.json (distributed coordination with ARES v1) — NAS path

Layer 1 (Cognition) — portable. No NAS path assumptions baked in.
Paths are injected at runtime from the embodiment layer.
"""

from __future__ import annotations

import sqlite3
import threading
import json
import time
from pathlib import Path

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS schema_version (
    version INTEGER PRIMARY KEY,
    applied_at REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS user_profile (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS facts (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    content TEXT NOT NULL,
    tags TEXT NOT NULL DEFAULT '[]',
    source TEXT NOT NULL DEFAULT 'main',
    learned_at REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS session_summaries (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    summary TEXT NOT NULL,
    session_start REAL NOT NULL,
    session_end REAL NOT NULL
);

CREATE TABLE IF NOT EXISTS skill_outcomes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    skill_name TEXT NOT NULL,
    tool_name TEXT NOT NULL,
    args TEXT NOT NULL,
    result TEXT NOT NULL,
    ok INTEGER NOT NULL,
    source TEXT NOT NULL DEFAULT 'main',
    executed_at REAL NOT NULL
);
"""

CURRENT_SCHEMA = 1


class Memory:
    """SQLite memory store shared across ARES agent + all subagents."""

    def __init__(self, path: Path):
        self.path = path
        self._lock = threading.Lock()
        self._conn: sqlite3.Connection | None = None

    def open(self):
        self._conn = sqlite3.connect(str(self.path), check_same_thread=False)
        self._conn.execute("PRAGMA journal_mode=WAL")
        self._conn.execute("PRAGMA foreign_keys=ON")
        self._apply_migrations()
        return self

    def _apply_migrations(self):
        with self._lock:
            version = self._get_schema_version()
            if version < CURRENT_SCHEMA:
                self._conn.executescript(SCHEMA_SQL)
                self._conn.execute(
                    "INSERT INTO schema_version (version, applied_at) VALUES (?, ?)",
                    (CURRENT_SCHEMA, time.time()),
                )
                self._conn.commit()

    def _get_schema_version(self) -> int:
        try:
            row = self._conn.execute("SELECT MAX(version) FROM schema_version").fetchone()
            return row[0] if row[0] is not None else 0
        except sqlite3.OperationalError:
            return 0

    def remember(self, content: str, tags: list[str] | None = None, source: str = "main") -> str:
        """Add a fact to memory. Returns the fact ID."""
        tags_json = json.dumps(tags or [])
        with self._lock:
            self._conn.execute(
                "INSERT INTO facts (content, tags, source, learned_at) VALUES (?, ?, ?, ?)",
                (content, tags_json, source, time.time()),
            )
            self._conn.commit()
            return str(self._conn.execute("SELECT last_insert_rowid()").fetchone()[0])

    def recall(
        self, tag: str | None = None, query: str | None = None, limit: int = 10, source: str | None = None
    ) -> list[dict]:
        """Recall facts. Filter by tag, query (substring), and/or source."""
        conditions = []
        params = []
        if tag:
            conditions.append("tags LIKE ?")
            params.append(f"%{tag}%")
        if query:
            conditions.append("content LIKE ?")
            params.append(f"%{query}%")
        if source:
            conditions.append("source = ?")
            params.append(source)

        where = " AND ".join(conditions) if conditions else "1=1"
        sql = f"SELECT id, content, tags, source, learned_at FROM facts WHERE {where} ORDER BY learned_at DESC LIMIT ?"
        params.append(limit)

        with self._lock:
            rows = self._conn.execute(sql, params).fetchall()
        return [
            {
                "id": str(r[0]),
                "content": r[1],
                "tags": json.loads(r[2]) if r[2] else [],
                "source": r[3],
                "learned_at": r[4],
            }
            for r in rows
        ]

    def forget(self, fact_id: str):
        with self._lock:
            self._conn.execute("DELETE FROM facts WHERE id = ?", (int(fact_id),))
            self._conn.commit()

    def set_profile(self, key: str, value: str):
        with self._lock:
            self._conn.execute(
                "INSERT OR REPLACE INTO user_profile (key, value, updated_at) VALUES (?, ?, ?)",
                (key, value, time.time()),
            )
            self._conn.commit()

    def get_profile(self, key: str) -> str | None:
        row = self._conn.execute("SELECT value FROM user_profile WHERE key = ?", (key,)).fetchone()
        return row[0] if row else None

    def log_skill_outcome(
        self, skill_name: str, tool_name: str, args: dict, result: dict, ok: bool, source: str = "main"
    ):
        with self._lock:
            self._conn.execute(
                "INSERT INTO skill_outcomes (skill_name, tool_name, args, result, ok, source, executed_at) "
                "VALUES (?, ?, ?, ?, ?, ?, ?)",
                (skill_name, tool_name, json.dumps(args), json.dumps(result), int(ok), source, time.time()),
            )
            self._conn.commit()

    def close(self):
        if self._conn:
            self._conn.close()
            self._conn = None

    def __enter__(self):
        return self.open()

    def __exit__(self, *_):
        self.close()


# ─── NAS Path Helpers (embodiment-injected) ───

_nas_obsidian_path: Path | None = None
_nas_brain_path: Path | None = None


def set_nas_paths(obsidian: Path | None = None, brain: Path | None = None):
    """Set NAS paths from embodiment layer. Call once at startup."""
    global _nas_obsidian_path, _nas_brain_path
    if obsidian:
        _nas_obsidian_path = obsidian
    if brain:
        _nas_brain_path = brain


def get_nas_paths() -> dict:
    return {"obsidian": _nas_obsidian_path, "brain": _nas_brain_path}
