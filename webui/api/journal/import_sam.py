"""
ARES Journal — SAM (Super Artificial Mind) importer.

Reads SAM conversation data from the SAM conversations directory.
Each conversation is a directory containing a conversation.json.
"""

import json
import time
from pathlib import Path
from typing import Optional

from .paths import sam_dir
from .schema import get_db, init_db


def import_sam(batch_id: str, since: Optional[float] = None) -> dict:
    """
    Import SAM conversations into the journal.

    Layout:
      <uuid>/conversation.json
    """
    sdir = sam_dir()
    if not sdir or not sdir.exists():
        return {"source": "sam", "imported_conversations": 0, "imported_messages": 0, "skipped": True, "reason": "SAM directory not found or not available on this platform"}

    jdb = init_db()
    conv_imported = 0
    msg_imported = 0

    for conv_dir in sorted(sdir.iterdir()):
        if not conv_dir.is_dir():
            continue

        conv_file = conv_dir / "conversation.json"
        if not conv_file.exists():
            continue

        session_id = conv_dir.name

        # Check if already imported
        existing = jdb.execute(
            "SELECT id FROM conversations WHERE source = 'sam' AND session_id = ?",
            (session_id,),
        ).fetchone()

        if existing:
            continue

        try:
            with open(conv_file) as f:
                data = json.load(f)
        except (json.JSONDecodeError, OSError):
            continue

        title = data.get("title", "") or data.get("sessionId", "")
        model = data.get("model", "")
        workspace = data.get("workingDirectory", "")
        messages = data.get("messages", [])

        # Parse timestamps
        created_at = None
        updated_at = None
        for ts_field in ["created", "updated"]:
            ts_val = data.get(ts_field)
            if ts_val and isinstance(ts_val, str):
                try:
                    ts = time.mktime(time.strptime(ts_val[:19], "%Y-%m-%dT%H:%M:%S"))
                    if ts_field == "created":
                        created_at = ts
                    else:
                        updated_at = ts
                except (ValueError, OverflowError):
                    pass

        if not created_at:
            created_at = conv_file.stat().st_mtime
        if not updated_at:
            updated_at = created_at

        if not title:
            title = f"SAM Session {session_id[:8]}"

        # Insert conversation
        jdb.execute(
            """INSERT OR IGNORE INTO conversations
               (source, session_id, title, model, workspace, created_at, updated_at,
                message_count, source_path, import_batch, import_ts, metadata)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                "sam",
                session_id,
                title,
                model,
                workspace,
                created_at,
                updated_at,
                len(messages),
                str(conv_file),
                batch_id,
                time.time(),
                json.dumps({
                    "is_from_api": data.get("isFromAPI", False),
                    "is_pinned": data.get("isPinned", False),
                    "settings": data.get("settings", {}),
                }),
            ),
        )
        conv_id = jdb.execute("SELECT last_insert_rowid()").fetchone()[0]

        if conv_id == 0:
            row = jdb.execute(
                "SELECT id FROM conversations WHERE source = 'sam' AND session_id = ?",
                (session_id,),
            ).fetchone()
            if not row:
                continue
            conv_id = row["id"]

        # Insert messages
        for seq, msg in enumerate(messages):
            role = msg.get("role", "")
            content = msg.get("content", "")

            if isinstance(content, list):
                text_parts = []
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "text":
                        text_parts.append(block.get("text", ""))
                content = "\n".join(text_parts)
            elif not isinstance(content, str):
                content = str(content)

            msg_ts = None
            for ts_field in ["timestamp", "created_at"]:
                ts_val = msg.get(ts_field)
                if ts_val:
                    if isinstance(ts_val, (int, float)):
                        msg_ts = ts_val
                    elif isinstance(ts_val, str):
                        try:
                            msg_ts = time.mktime(time.strptime(ts_val[:19], "%Y-%m-%dT%H:%M:%S"))
                        except (ValueError, OverflowError):
                            pass
                    break

            jdb.execute(
                """INSERT INTO messages
                   (conversation_id, seq, role, content, timestamp, model, metadata)
                   VALUES (?, ?, ?, ?, ?, ?, ?)""",
                (
                    conv_id,
                    seq,
                    role,
                    (content or "")[:100000],
                    msg_ts,
                    msg.get("model", model),
                    json.dumps({}),
                ),
            )
            msg_imported += 1

        conv_imported += 1

    jdb.commit()
    return {
        "source": "sam",
        "imported_conversations": conv_imported,
        "imported_messages": msg_imported,
        "skipped": False,
    }