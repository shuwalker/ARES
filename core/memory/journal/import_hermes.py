"""
ARES Journal — Hermes Agent importer.

Reads all sessions and messages from the Hermes state.db SQLite database
and imports them into the journal.
"""

import sqlite3
from typing import Optional

from .paths import hermes_db
from .schema import get_db, init_db


def import_hermes(batch_id: str, since: Optional[float] = None) -> dict:
    """
    Import all Hermes sessions and messages into the journal.

    Args:
        batch_id: UUID for this import run.
        since: Optional unix timestamp to only import sessions updated after this time.

    Returns:
        Dict with import statistics.
    """
    db_path = hermes_db()
    if not db_path.exists():
        return {"source": "hermes", "imported_conversations": 0, "imported_messages": 0, "skipped": True, "reason": f"{db_path} not found"}

    src = sqlite3.connect(str(db_path))
    src.row_factory = sqlite3.Row
    jdb = init_db()

    # Get sessions, optionally filtered by time
    sql = """
        SELECT id, source, title, model, cwd, started_at, ended_at,
               message_count, tool_call_count, input_tokens, output_tokens,
               git_branch, git_repo_root, display_name, chat_id, chat_type
        FROM sessions
    """
    params: list = []
    if since:
        sql += " WHERE started_at > ?"
        params.append(since)

    sessions = src.execute(sql, params).fetchall()

    conv_imported = 0
    msg_imported = 0

    for sess in sessions:
        # Check if already imported
        existing = jdb.execute(
            "SELECT id FROM conversations WHERE source = 'hermes' AND session_id = ?",
            (sess["id"],),
        ).fetchone()

        if existing:
            # Skip re-import for now — we can add incremental later
            continue

        # Insert conversation
        jdb.execute(
            """INSERT OR IGNORE INTO conversations
               (source, session_id, title, model, workspace, created_at, updated_at,
                message_count, source_path, import_batch, import_ts, metadata)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                "hermes",
                sess["id"],
                sess["title"] or sess["display_name"] or "",
                sess["model"] or "",
                sess["cwd"] or "",
                sess["started_at"],
                sess["ended_at"] or sess["started_at"],
                sess["message_count"] or 0,
                str(db_path),
                batch_id,
                __import__("time").time(),
                __import__("json").dumps({
                    "source_type": sess["source"],
                    "chat_id": sess["chat_id"],
                    "chat_type": sess["chat_type"],
                    "tool_call_count": sess["tool_call_count"],
                    "input_tokens": sess["input_tokens"],
                    "output_tokens": sess["output_tokens"],
                    "git_branch": sess["git_branch"],
                    "git_repo_root": sess["git_repo_root"],
                }),
            ),
        )
        conv_id = jdb.execute("SELECT last_insert_rowid()").fetchone()[0]

        # If we didn't get an insert (already exists), find the existing one
        if conv_id == 0:
            row = jdb.execute(
                "SELECT id FROM conversations WHERE source = 'hermes' AND session_id = ?",
                (sess["id"],),
            ).fetchone()
            if not row:
                continue
            conv_id = row["id"]

        # Get messages for this session
        msgs = src.execute(
            """SELECT id, session_id, role, content, tool_name, tool_calls,
                      timestamp, token_count, finish_reason, reasoning_content
               FROM messages
               WHERE session_id = ? AND active = 1
               ORDER BY timestamp""",
            (sess["id"],),
        ).fetchall()

        for seq, msg in enumerate(msgs):
            jdb.execute(
                """INSERT INTO messages
                   (conversation_id, seq, role, content, timestamp, model,
                    tool_name, token_count, metadata)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    conv_id,
                    seq,
                    msg["role"],
                    (msg["content"] or "")[:100000],  # Cap at 100K chars per message
                    msg["timestamp"],
                    sess["model"] or "",
                    msg["tool_name"] or None,
                    msg["token_count"],
                    __import__("json").dumps({
                        "finish_reason": msg["finish_reason"],
                        "has_reasoning": bool(msg["reasoning_content"]),
                        "has_tool_calls": bool(msg["tool_calls"]),
                    }),
                ),
            )
            msg_imported += 1

        conv_imported += 1

    jdb.commit()
    src.close()

    return {
        "source": "hermes",
        "imported_conversations": conv_imported,
        "imported_messages": msg_imported,
        "skipped": False,
    }