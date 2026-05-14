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
import math
import re
import time
from pathlib import Path


# ─── MEMTIER five-signal scoring ───
# Composite recall score = recency × frequency × relevance × importance × decay.
# Each signal is normalized to (0, 1] (relevance can hit 0 when a query is given
# and shares no tokens with the candidate; that's intentional — it filters out
# irrelevant items when a query is supplied).

_TOKEN_RE = re.compile(r"\w+")
_RECENCY_TAU_DAYS = 7.0      # sharp recency: half-life ≈ 4.85 days
_DECAY_HALF_LIFE_DAYS = 30.0  # smooth long-tail decay
_FREQUENCY_REFERENCE = 10.0   # smoothing constant: never zero, asymptotes to 1
_CANDIDATE_POOL_MULT = 20     # how many candidates to score per requested item
_CANDIDATE_POOL_MAX = 500


def _tokenize(text: str | None) -> set[str]:
    if not text:
        return set()
    return {t.lower() for t in _TOKEN_RE.findall(text)}


def _cosine_overlap(a: set[str], b: set[str]) -> float:
    """Cosine similarity between two token bags (binary TF). Cheap proxy for an
    embedding-based similarity — no model dependency, works on raw content."""
    if not a or not b:
        return 0.0
    inter = len(a & b)
    if inter == 0:
        return 0.0
    return inter / math.sqrt(len(a) * len(b))


def _recency_score(age_seconds: float, tau_days: float = _RECENCY_TAU_DAYS) -> float:
    age_days = max(age_seconds, 0.0) / 86400.0
    return math.exp(-age_days / tau_days)


def _decay_score(age_seconds: float, half_life_days: float = _DECAY_HALF_LIFE_DAYS) -> float:
    age_days = max(age_seconds, 0.0) / 86400.0
    return 0.5 ** (age_days / half_life_days)


def _frequency_score(recall_count: int) -> float:
    """Smooth saturating function: 0 recalls → 0.1, 10 → 0.55, 100 → 0.92."""
    n = max(recall_count, 0)
    return (n + 1) / (n + _FREQUENCY_REFERENCE)



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
    learned_at REAL NOT NULL,
    importance REAL NOT NULL DEFAULT 0.5,
    recall_count INTEGER NOT NULL DEFAULT 0,
    last_recalled_at REAL
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

CURRENT_SCHEMA = 2


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
                # v2: MEMTIER scoring columns. SQLite has no idempotent
                # ADD COLUMN — on fresh installs the columns are already
                # present from SCHEMA_SQL and the ALTER raises; we swallow.
                for col_def in (
                    "importance REAL NOT NULL DEFAULT 0.5",
                    "recall_count INTEGER NOT NULL DEFAULT 0",
                    "last_recalled_at REAL",
                ):
                    try:
                        self._conn.execute(f"ALTER TABLE facts ADD COLUMN {col_def}")
                    except sqlite3.OperationalError:
                        pass
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

    def remember(self, content: str, tags: list[str] | None = None, source: str = "main",
                 importance: float = 0.5) -> str:
        """Add a fact to memory. Returns the fact ID.

        ``importance`` is the MEMTIER quality signal in [0.0, 1.0]; clamped on write.
        """
        tags_json = json.dumps(tags or [])
        importance = max(0.0, min(1.0, float(importance)))
        with self._lock:
            self._conn.execute(
                "INSERT INTO facts (content, tags, source, learned_at, importance) "
                "VALUES (?, ?, ?, ?, ?)",
                (content, tags_json, source, time.time(), importance),
            )
            self._conn.commit()
            return str(self._conn.execute("SELECT last_insert_rowid()").fetchone()[0])

    def recall(self, tag: str | None = None, query: str | None = None, limit: int = 10,
               source: str | None = None) -> list[dict]:
        """Recall facts ranked by MEMTIER five-signal composite score:

            score = recency × frequency × relevance × importance × decay

        ``tag`` and ``source`` remain hard SQL filters (they pick the candidate
        set). ``query`` becomes a soft relevance signal via token-bag cosine
        similarity over fact content. When ``query`` is given, candidates that
        share no tokens with it are dropped.

        As a side effect, returned facts have their ``recall_count`` incremented
        and ``last_recalled_at`` updated — this feeds the frequency signal back
        into future recalls.
        """
        # 1. Hard filters → candidate pool (newest first, capped).
        conditions = []
        params: list = []
        if tag:
            conditions.append("tags LIKE ?")
            params.append(f"%{tag}%")
        if source:
            conditions.append("source = ?")
            params.append(source)
        where = " AND ".join(conditions) if conditions else "1=1"

        pool_size = min(max(limit * _CANDIDATE_POOL_MULT, 50), _CANDIDATE_POOL_MAX)
        sql = (
            "SELECT id, content, tags, source, learned_at, "
            "COALESCE(importance, 0.5), COALESCE(recall_count, 0) "
            f"FROM facts WHERE {where} ORDER BY learned_at DESC LIMIT ?"
        )
        with self._lock:
            rows = self._conn.execute(sql, [*params, pool_size]).fetchall()

        if not rows:
            return []

        # 2. Score each candidate.
        now = time.time()
        query_tokens = _tokenize(query) if query else None
        scored = []
        for fid, content, tags_json, src, learned_at, importance, recall_count in rows:
            age = max(now - (learned_at or now), 0.0)

            recency = _recency_score(age)
            decay = _decay_score(age)
            frequency = _frequency_score(recall_count)
            importance = float(importance) if importance is not None else 0.5

            if query_tokens is not None:
                relevance = _cosine_overlap(query_tokens, _tokenize(content))
                # When a query is supplied, drop irrelevant candidates entirely
                # rather than returning them with score 0.
                if relevance == 0.0:
                    continue
            else:
                relevance = 1.0

            score = recency * frequency * relevance * importance * decay
            scored.append({
                "id": str(fid),
                "content": content,
                "tags": json.loads(tags_json) if tags_json else [],
                "source": src,
                "learned_at": learned_at,
                "recall_count": recall_count,
                "score": score,
                "score_breakdown": {
                    "recency": recency,
                    "frequency": frequency,
                    "relevance": relevance,
                    "importance": importance,
                    "decay": decay,
                },
            })

        # 3. Rank by composite score, tie-break by recency.
        scored.sort(key=lambda r: (r["score"], r["learned_at"] or 0.0), reverse=True)
        top = scored[:limit]

        # 4. Update frequency signal for the returned facts.
        if top:
            ids = [int(r["id"]) for r in top]
            placeholders = ",".join("?" * len(ids))
            with self._lock:
                self._conn.execute(
                    f"UPDATE facts SET recall_count = COALESCE(recall_count, 0) + 1, "
                    f"last_recalled_at = ? WHERE id IN ({placeholders})",
                    [now, *ids],
                )
                self._conn.commit()

        return top

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


def open_default() -> Memory:
    """Open the default ARES memory store at ~/.ares/memory.db (opened, caller closes)."""
    from ..config import ares_home
    return Memory(ares_home() / "memory.db").open()
