"""
ARES SI — Memory lifecycle.

Ingest → Classify → Label → Dedup → Score → Store → Consolidate → Retrieve → Correct

Uses the actual Journal DB schema:
- conversations: id (INTEGER PK), session_id (TEXT), source, title, metadata (JSON), created_at, updated_at
- messages: id (INTEGER PK), conversation_id (INTEGER FK), seq, role, content, timestamp, metadata (JSON)

Sensitivity, importance, and is_decision are stored in conversations.metadata JSON.
"""

from __future__ import annotations

import json
import os
import sqlite3
import time
from pathlib import Path
from typing import Any

from api.si.types import DataClassification, MemoryItem, PUBLIC, PERSONAL, PRIVATE, SENSITIVE, SECRET


def _journal_db_path() -> Path:
    ares_home = os.environ.get("ARES_HOME", os.path.expanduser("~/.ares"))
    return Path(ares_home) / "journal" / "journal.db"


def _get_db() -> sqlite3.Connection:
    db_path = _journal_db_path()
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL")
    return conn


def _ensure_tables(conn: sqlite3.Connection) -> None:
    """Ensure memory lifecycle tables exist."""
    conn.executescript("""
        CREATE TABLE IF NOT EXISTS memory_labels (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            memory_id TEXT NOT NULL,
            label TEXT NOT NULL,
            source TEXT DEFAULT 'auto',
            created_at REAL NOT NULL,
            UNIQUE(memory_id, label)
        );
        CREATE INDEX IF NOT EXISTS idx_memory_labels_memory ON memory_labels(memory_id);
        CREATE INDEX IF NOT EXISTS idx_memory_labels_label ON memory_labels(label);

        CREATE TABLE IF NOT EXISTS memory_consolidations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            summary_id TEXT NOT NULL UNIQUE,
            source_ids_json TEXT NOT NULL,
            created_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS memory_corrections (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            original_id TEXT NOT NULL,
            correction_id TEXT NOT NULL,
            reason TEXT NOT NULL,
            created_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_memory_corrections_original ON memory_corrections(original_id);

        CREATE TABLE IF NOT EXISTS memory_access_log (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            memory_id TEXT NOT NULL,
            accessed_at REAL NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_memory_access_memory ON memory_access_log(memory_id);
    """)


def _get_metadata(conn: sqlite3.Connection, session_id: str) -> dict[str, Any]:
    """Get the metadata JSON for a conversation."""
    row = conn.execute(
        "SELECT metadata FROM conversations WHERE session_id = ?", (session_id,)
    ).fetchone()
    if row is None or not row["metadata"]:
        return {}
    try:
        return json.loads(row["metadata"])
    except (json.JSONDecodeError, TypeError):
        return {}


def _set_metadata(conn: sqlite3.Connection, session_id: str, meta: dict[str, Any]) -> None:
    """Set the metadata JSON for a conversation."""
    conn.execute(
        "UPDATE conversations SET metadata = ? WHERE session_id = ?",
        (json.dumps(meta), session_id),
    )


def _get_content(conn: sqlite3.Connection, conversation_id: int) -> str:
    """Get the full text content of a conversation's messages."""
    rows = conn.execute(
        "SELECT content FROM messages WHERE conversation_id = ? ORDER BY seq",
        (conversation_id,),
    ).fetchall()
    return " ".join(r["content"] or "" for r in rows)


# ── Ingest ──────────────────────────────────────────────────────────────

def ingest_memory(
    source: str,
    content: str,
    metadata: dict[str, Any] | None = None,
    *,
    sensitivity: DataClassification | None = None,
    is_decision: bool = False,
) -> str:
    """Ingest a new memory into the Journal. Returns the session_id as memory_id."""
    from api.si.trust_engine import classify_data

    conn = _get_db()
    _ensure_tables(conn)

    memory_id = f"mem_{int(time.time() * 1000)}_{os.urandom(4).hex()}"
    now = time.time()

    if sensitivity is None:
        sensitivity = classify_data(content, metadata or {})

    meta = (metadata or {}).copy()
    meta["si_sensitivity"] = sensitivity.value
    meta["si_importance"] = 0.3
    meta["si_is_decision"] = is_decision
    meta["si_memory_id"] = memory_id

    conn.execute(
        """INSERT INTO conversations
           (session_id, source, title, created_at, updated_at, message_count, metadata)
           VALUES (?, ?, ?, ?, ?, 1, ?)""",
        (memory_id, source, (metadata or {}).get("title", content[:80]), now, now, json.dumps(meta)),
    )
    conv_row = conn.execute(
        "SELECT id FROM conversations WHERE session_id = ?", (memory_id,)
    ).fetchone()
    conv_id = conv_row["id"]

    conn.execute(
        "INSERT INTO messages (conversation_id, seq, role, content, timestamp) VALUES (?, 0, 'system', ?, ?)",
        (conv_id, content, now),
    )
    conn.commit()
    conn.close()
    return memory_id


# ── Classify ────────────────────────────────────────────────────────────

def classify_memory(memory_id: str) -> DataClassification:
    """Classify a memory's sensitivity using the trust engine."""
    from api.si.trust_engine import classify_data

    conn = _get_db()
    row = conn.execute(
        "SELECT id, source FROM conversations WHERE session_id = ?", (memory_id,)
    ).fetchone()

    if row is None:
        conn.close()
        return PERSONAL

    content = _get_content(conn, row["id"])
    sensitivity = classify_data(content, {"source": row["source"]})

    meta = _get_metadata(conn, memory_id)
    meta["si_sensitivity"] = sensitivity.value
    _set_metadata(conn, memory_id, meta)
    conn.commit()
    conn.close()

    return sensitivity


# ── Dedup ───────────────────────────────────────────────────────────────

def dedup_memory(content: str, *, threshold: float = 0.85) -> str | None:
    """Check if content is a near-duplicate of an existing memory via FTS5.

    Returns existing memory_id (session_id) if duplicate, None if new.
    """
    conn = _get_db()
    try:
        rows = conn.execute(
            """SELECT c.session_id, c.id
               FROM messages_fts
               JOIN messages m ON messages_fts.rowid = m.id
               JOIN conversations c ON m.conversation_id = c.id
               WHERE messages_fts MATCH ?
               LIMIT 5""",
            (content[:200],),
        ).fetchall()
    except sqlite3.OperationalError:
        conn.close()
        return None

    if not rows:
        conn.close()
        return None

    words = set(content.lower().split())
    if not words:
        conn.close()
        return None

    for row in rows:
        existing = _get_content(conn, row["id"])
        existing_words = set(existing.lower().split())
        if not existing_words:
            continue
        overlap = len(words & existing_words) / len(words | existing_words)
        if overlap >= threshold:
            conn.close()
            return row["session_id"]

    conn.close()
    return None


# ── Score ───────────────────────────────────────────────────────────────

def score_importance(memory_id: str) -> float:
    """Score importance (0.0–1.0) based on recency, decision weight, corrections, access count."""
    conn = _get_db()
    row = conn.execute(
        "SELECT created_at, metadata FROM conversations WHERE session_id = ?",
        (memory_id,),
    ).fetchone()

    if row is None:
        conn.close()
        return 0.3

    meta = _get_metadata(conn, memory_id)
    now = time.time()
    age_days = (now - (row["created_at"] or now)) / 86400.0

    recency = max(0.0, 1.0 - (age_days / 90.0))
    decision_boost = 0.3 if meta.get("si_is_decision") else 0.0

    correction_count = conn.execute(
        "SELECT COUNT(*) FROM memory_corrections WHERE original_id = ?",
        (memory_id,),
    ).fetchone()[0]
    correction_boost = min(0.3, correction_count * 0.15)

    access_count = conn.execute(
        "SELECT COUNT(*) FROM memory_access_log WHERE memory_id = ?",
        (memory_id,),
    ).fetchone()[0]
    access_boost = min(0.2, access_count * 0.02)

    conn.close()

    score = recency * 0.4 + decision_boost + correction_boost + access_boost
    score = max(0.0, min(1.0, score))

    conn = _get_db()
    meta["si_importance"] = score
    _set_metadata(conn, memory_id, meta)
    conn.commit()
    conn.close()

    return score


# ── Retrieve ─────────────────────────────────────────────────────────────

def retrieve_memories(
    query: str,
    *,
    limit: int = 10,
    max_sensitivity: DataClassification = PERSONAL,
) -> list[MemoryItem]:
    """Retrieve relevant memories, filtered by sensitivity."""
    conn = _get_db()
    _ensure_tables(conn)

    allowed = _allowed_sensitivities(max_sensitivity)

    try:
        rows = conn.execute(
            f"""SELECT c.session_id, c.source, c.metadata, c.created_at
               FROM messages_fts
               JOIN messages m ON messages_fts.rowid = m.id
               JOIN conversations c ON m.conversation_id = c.id
               WHERE messages_fts MATCH ?
               GROUP BY c.id
               ORDER BY c.created_at DESC
               LIMIT ?""",
            (query or "*", limit),
        ).fetchall()
    except sqlite3.OperationalError:
        conn.close()
        return []

    memories = []
    now = time.time()
    for row in rows:
        meta = {}
        try:
            meta = json.loads(row["metadata"] or "{}")
        except (json.JSONDecodeError, TypeError):
            pass

        sensitivity_str = meta.get("si_sensitivity", "personal")
        if sensitivity_str not in allowed:
            continue

        try:
            sensitivity = DataClassification(sensitivity_str)
        except ValueError:
            sensitivity = PERSONAL

        # Get content
        conv_row = conn.execute(
            "SELECT id FROM conversations WHERE session_id = ?", (row["session_id"],)
        ).fetchone()
        content = _get_content(conn, conv_row["id"]) if conv_row else ""

        if not content.strip():
            continue

        memories.append(MemoryItem(
            memory_id=row["session_id"],
            content=content[:500],
            source=row["source"] or "unknown",
            sensitivity=sensitivity,
            importance=float(meta.get("si_importance", 0.3)),
            created_at=row["created_at"] or 0.0,
        ))

        conn.execute(
            "INSERT INTO memory_access_log (memory_id, accessed_at) VALUES (?, ?)",
            (row["session_id"], now),
        )

    conn.commit()
    conn.close()
    return memories


# ── Correct ─────────────────────────────────────────────────────────────

def correct_memory(memory_id: str, correction: str, reason: str) -> str:
    """Record a user correction. Returns the correction memory_id."""
    correction_id = ingest_memory(
        source="user_correction",
        content=correction,
        metadata={"original_id": memory_id, "reason": reason},
        is_decision=True,
    )

    conn = _get_db()
    _ensure_tables(conn)
    conn.execute(
        "INSERT INTO memory_corrections (original_id, correction_id, reason, created_at) VALUES (?, ?, ?, ?)",
        (memory_id, correction_id, reason, time.time()),
    )
    conn.commit()
    conn.close()

    score_importance(memory_id)
    return correction_id


def delete_memory(memory_id: str) -> bool:
    """Soft-delete a memory (marks as deleted in metadata, preserves audit trail)."""
    conn = _get_db()
    meta = _get_metadata(conn, memory_id)
    meta["si_deleted"] = True
    meta["si_deleted_at"] = time.time()
    _set_metadata(conn, memory_id, meta)
    conn.commit()
    conn.close()
    return True


def get_memory_history(memory_id: str) -> list[dict[str, Any]]:
    """Get the full correction history for a memory."""
    conn = _get_db()
    _ensure_tables(conn)
    rows = conn.execute(
        "SELECT correction_id, reason, created_at FROM memory_corrections WHERE original_id = ? ORDER BY created_at",
        (memory_id,),
    ).fetchall()
    conn.close()
    return [{"correction_id": r["correction_id"], "reason": r["reason"], "created_at": r["created_at"]} for r in rows]


def backfill_importance() -> int:
    """Score importance for all existing conversations that don't have a score yet."""
    conn = _get_db()
    rows = conn.execute(
        "SELECT session_id, metadata FROM conversations"
    ).fetchall()
    conn.close()

    count = 0
    for row in rows:
        meta = {}
        try:
            meta = json.loads(row["metadata"] or "{}")
        except (json.JSONDecodeError, TypeError):
            pass
        if "si_importance" not in meta:
            score_importance(row["session_id"])
            count += 1

    return count


# ── Helpers ──────────────────────────────────────────────────────────────

def _allowed_sensitivities(max_sensitivity: DataClassification) -> list[str]:
    order = [PUBLIC, PERSONAL, PRIVATE, SENSITIVE, SECRET]
    result = []
    for s in order:
        result.append(s.value)
        if s == max_sensitivity:
            break
    return result
