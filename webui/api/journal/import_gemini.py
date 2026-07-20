"""
ARES Journal — Gemini/Antigravity IDE importer.

Reads Gemini conversation data from the Antigravity IDE local storage.
Each conversation is stored as a SQLite database with protobuf-encoded steps.

Since the step content is protobuf-encoded, this importer extracts what it can:
- Trajectory metadata (IDs, types)
- Step metadata (types, timestamps)
- Full text from the Antigravity state.vscdb trajectory summaries
"""

import json
import os
import sqlite3
import time
from pathlib import Path
from typing import Optional

from .schema import get_db, init_db


GEMINI_CONVERSATIONS_DIR = Path.home() / ".gemini" / "antigravity-ide" / "conversations"
ANTIGRAVITY_STATE_DB = Path.home() / "Library" / "Application Support" / "Antigravity IDE" / "User" / "globalStorage" / "state.vscdb"


def import_gemini(batch_id: str, since: Optional[float] = None) -> dict:
    """
    Import Gemini/Antigravity conversations into the journal.

    Two data sources:
    1. ~/.gemini/antigravity-ide/conversations/ — SQLite DBs with protobuf step content
    2. Antigravity state.vscdb — Contains trajectory summaries with titles

    The protobuf content in the step_payload is not easily readable without the
    protobuf schema, so we import metadata and any extractable text.
    """
    jdb = init_db()
    conv_imported = 0
    msg_imported = 0

    # First, try to get titles from the Antigravity state.vscdb
    titles = {}
    if ANTIGRAVITY_STATE_DB.exists():
        try:
            state_db = sqlite3.connect(str(ANTIGRAVITY_STATE_DB))
            state_db.row_factory = sqlite3.Row
            # Get trajectory summaries - these contain base64-encoded protobuf with titles
            rows = state_db.execute(
                "SELECT key, value FROM ItemTable WHERE key LIKE '%trajectorySummaries%'"
            ).fetchall()
            for row in rows:
                try:
                    data = json.loads(row["value"])
                    if isinstance(data, list):
                        for item in data:
                            conv_id = item.get("id", "")
                            title = item.get("title", "")
                            if conv_id and title:
                                titles[conv_id] = title
                except (json.JSONDecodeError, TypeError):
                    pass
            state_db.close()
        except Exception:
            pass

    # Import conversation databases
    if not GEMINI_CONVERSATIONS_DIR.exists():
        return {"source": "gemini", "imported_conversations": 0, "imported_messages": 0, "skipped": True, "reason": f"{GEMINI_CONVERSATIONS_DIR} not found"}

    for db_path in sorted(GEMINI_CONVERSATIONS_DIR.glob("*.db")):
        session_id = db_path.stem  # UUID like a5a7a951-733e-4af4-829c-7bcedc5fca51

        # Check if already imported
        existing = jdb.execute(
            "SELECT id FROM conversations WHERE source = 'gemini' AND session_id = ?",
            (session_id,),
        ).fetchone()

        if existing:
            continue

        try:
            conv_db = sqlite3.connect(str(db_path))
            conv_db.row_factory = sqlite3.Row

            # Get step count
            step_count = conv_db.execute("SELECT COUNT(*) as cnt FROM steps").fetchone()["cnt"]

            # Get trajectory metadata
            meta = conv_db.execute("SELECT * FROM trajectory_meta").fetchone()

            # Get any readable text from steps
            # The step_payload is protobuf, but we can try to extract readable strings
            steps = conv_db.execute(
                "SELECT idx, step_type, status FROM steps ORDER BY idx"
            ).fetchall()

            title = titles.get(session_id, f"Gemini Session {session_id[:8]}")

            # Create conversation entry
            created_at = db_path.stat().st_mtime
            model = "gemini"

            jdb.execute(
                """INSERT OR IGNORE INTO conversations
                   (source, session_id, title, model, workspace, created_at, updated_at,
                    message_count, source_path, import_batch, import_ts, metadata)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    "gemini",
                    session_id,
                    title,
                    model,
                    "",
                    created_at,
                    db_path.stat().st_mtime,
                    step_count,
                    str(db_path),
                    batch_id,
                    time.time(),
                    json.dumps({
                        "trajectory_type": dict(meta)["trajectory_type"] if meta else None,
                        "cascade_id": dict(meta)["cascade_id"] if meta else None,
                        "source": dict(meta)["source"] if meta else None,
                        "has_protobuf_content": True,
                        "note": "Step content is protobuf-encoded and not directly readable",
                    }),
                ),
            )
            conv_id = jdb.execute("SELECT last_insert_rowid()").fetchone()[0]

            if conv_id == 0:
                row = jdb.execute(
                    "SELECT id FROM conversations WHERE source = 'gemini' AND session_id = ?",
                    (session_id,),
                ).fetchone()
                if not row:
                    conv_db.close()
                    continue
                conv_id = row["id"]

            # Add step entries as messages (with metadata only, content is protobuf)
            for step in steps:
                step_type = step["step_type"]
                # Map step types to roles (best guess)
                # step_type 0 = user turn, 1 = assistant turn, 2+ = tool/output
                role_map = {0: "user", 1: "assistant"}
                role = role_map.get(step_type, "tool")

                jdb.execute(
                    """INSERT INTO messages
                       (conversation_id, seq, role, content, timestamp, model, metadata)
                       VALUES (?, ?, ?, ?, ?, ?, ?)""",
                    (
                        conv_id,
                        step["idx"],
                        role,
                        f"[Protobuf step type={step_type}, status={step['status']}]",
                        None,
                        "gemini",
                        json.dumps({
                            "step_type": step["step_type"],
                            "status": step["status"],
                            "has_subtrajectory": False,
                        }),
                    ),
                )
                msg_imported += 1

            conv_imported += 1
            conv_db.close()

        except Exception:
            continue

    jdb.commit()
    return {
        "source": "gemini",
        "imported_conversations": conv_imported,
        "imported_messages": msg_imported,
        "skipped": False,
        "note": "Gemini step content is protobuf-encoded; only metadata is imported. Full text requires protobuf schema.",
    }