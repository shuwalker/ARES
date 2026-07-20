"""
ARES Journal — Schema and database management.

Creates and manages the unified conversation store at ~/.ares/journal/journal.db
with FTS5 full-text search across all imported conversations.
"""

import json
import os
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

JOURNAL_DIR = Path(os.environ.get("ARES_HOME", Path.home() / ".ares")) / "journal"
DB_PATH = JOURNAL_DIR / "journal.db"

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS conversations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source TEXT NOT NULL,           -- hermes, claude_code, grok, gemini, codex, sam, imessage
    session_id TEXT NOT NULL,       -- original session identifier
    title TEXT,                     -- human-readable session title
    model TEXT,                     -- AI model used
    workspace TEXT,                 -- working directory or context
    created_at REAL,               -- unix timestamp
    updated_at REAL,               -- unix timestamp
    message_count INTEGER DEFAULT 0,
    source_path TEXT,              -- original data location for re-import
    import_batch TEXT,             -- UUID of the import run
    import_ts REAL,               -- when we imported this
    metadata TEXT,                  -- JSON blob for source-specific fields
    UNIQUE(source, session_id)
);

CREATE TABLE IF NOT EXISTS messages (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id INTEGER NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    seq INTEGER NOT NULL,          -- message order within conversation
    role TEXT NOT NULL,            -- user, assistant, tool, system, reasoning
    content TEXT,                  -- message text content
    timestamp REAL,               -- unix timestamp
    model TEXT,                    -- model that generated this message (if known)
    tool_name TEXT,                -- for tool calls: which tool
    token_count INTEGER,          -- if available
    metadata TEXT,                  -- JSON blob for source-specific fields
    FOREIGN KEY (conversation_id) REFERENCES conversations(id)
);

CREATE INDEX IF NOT EXISTS idx_messages_conv ON messages(conversation_id, seq);
CREATE INDEX IF NOT EXISTS idx_messages_role ON messages(conversation_id, role);
CREATE INDEX IF NOT EXISTS idx_conversations_source ON conversations(source);
CREATE INDEX IF NOT EXISTS idx_conversations_created ON conversations(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversations_updated ON conversations(updated_at DESC);

-- FTS5 for full-text search across all message content
CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts USING fts5(
    content,
    content='messages',
    content_rowid='id',
    tokenize='porter unicode61'
);

-- Triggers to keep FTS in sync
CREATE TRIGGER IF NOT EXISTS messages_fts_insert AFTER INSERT ON messages BEGIN
    INSERT INTO messages_fts(rowid, content) VALUES (
        new.id,
        COALESCE(new.content, '') || ' ' || COALESCE(new.tool_name, '')
    );
END;

CREATE TRIGGER IF NOT EXISTS messages_fts_delete AFTER DELETE ON messages BEGIN
    DELETE FROM messages_fts WHERE rowid = old.id;
END;

CREATE TRIGGER IF NOT EXISTS messages_fts_update AFTER UPDATE ON messages BEGIN
    DELETE FROM messages_fts WHERE rowid = old.id;
    INSERT INTO messages_fts(rowid, content) VALUES (
        new.id,
        COALESCE(new.content, '') || ' ' || COALESCE(new.tool_name, '')
    );
END;
"""


def get_db() -> sqlite3.Connection:
    """Get a connection to the journal database, creating it if needed."""
    JOURNAL_DIR.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(str(DB_PATH))
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA foreign_keys=ON")
    db.row_factory = sqlite3.Row
    return db


def init_db() -> sqlite3.Connection:
    """Initialize the journal database schema."""
    db = get_db()
    db.executescript(SCHEMA_SQL)
    db.commit()
    return db


def search(query: str, source: Optional[str] = None, limit: int = 20) -> list[dict]:
    """Full-text search across all imported conversations."""
    db = get_db()
    # Use subquery to find matching conversation IDs, then get details
    matching_conv_ids = db.execute(
        """SELECT DISTINCT c.id as cid
           FROM messages_fts m
           JOIN messages msg ON msg.id = m.rowid
           JOIN conversations c ON c.id = msg.conversation_id
           WHERE messages_fts MATCH ?
           """ + (" AND c.source = ?" if source else ""),
        [query] + ([source] if source else []),
    ).fetchall()
    conv_ids = [r["cid"] for r in matching_conv_ids[:limit]]

    if not conv_ids:
        return []

    # Get conversation details + best matching snippet per conversation
    results = []
    for cid in conv_ids:
        conv = db.execute(
            "SELECT * FROM conversations WHERE id = ?", (cid,)
        ).fetchone()
        if not conv:
            continue
        # Get the best matching message snippet
        best_msg = db.execute(
            """SELECT msg.id, msg.content
               FROM messages_fts m
               JOIN messages msg ON msg.id = m.rowid
               WHERE m.messages_fts MATCH ? AND msg.conversation_id = ?
               ORDER BY rank LIMIT 1""",
            (query, cid),
        ).fetchone()
        snippet = ""
        if best_msg and best_msg["content"]:
            content = best_msg["content"]
            # Find the search term in the content and extract surrounding context
            lower_content = content.lower()
            lower_query = query.lower()
            pos = lower_content.find(lower_query)
            if pos >= 0:
                start = max(0, pos - 80)
                end = min(len(content), pos + len(query) + 80)
                snippet = content[start:end]
                if start > 0:
                    snippet = "..." + snippet
                if end < len(content):
                    snippet = snippet + "..."
            else:
                snippet = content[:160]

        results.append({
            "id": conv["id"],
            "source": conv["source"],
            "session_id": conv["session_id"],
            "title": conv["title"],
            "model": conv["model"],
            "workspace": conv["workspace"],
            "created_at": conv["created_at"],
            "updated_at": conv["updated_at"],
            "message_count": conv["message_count"],
            "snippet": snippet,
        })
    return results


def get_conversation(conversation_id: int) -> Optional[dict]:
    """Get a conversation with all its messages."""
    db = get_db()
    conv = db.execute(
        "SELECT * FROM conversations WHERE id = ?", (conversation_id,)
    ).fetchone()
    if not conv:
        return None
    msgs = db.execute(
        "SELECT * FROM messages WHERE conversation_id = ? ORDER BY seq",
        (conversation_id,),
    ).fetchall()
    return {"conversation": dict(conv), "messages": [dict(m) for m in msgs]}


def list_conversations(source: Optional[str] = None, limit: int = 50) -> list[dict]:
    """List conversations, most recently updated first."""
    db = get_db()
    sql = "SELECT * FROM conversations"
    params: list = []
    if source:
        sql += " WHERE source = ?"
        params.append(source)
    sql += " ORDER BY updated_at DESC LIMIT ?"
    params.append(str(limit))
    return [dict(r) for r in db.execute(sql, params).fetchall()]


def stats() -> dict:
    """Get import statistics."""
    db = get_db()
    try:
        conv_count = db.execute("SELECT COUNT(*) FROM conversations").fetchone()[0]
        msg_count = db.execute("SELECT COUNT(*) FROM messages").fetchone()[0]
        sources = db.execute(
            "SELECT source, COUNT(*) as cnt FROM conversations GROUP BY source ORDER BY cnt DESC"
        ).fetchall()
        return {
            "total_conversations": conv_count,
            "total_messages": msg_count,
            "by_source": {r["source"]: r["cnt"] for r in sources},
        }
    except sqlite3.OperationalError:
        return {"total_conversations": 0, "total_messages": 0, "by_source": {}}