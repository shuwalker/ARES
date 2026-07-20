"""
ARES Journal — Codex importer.

Reads session data from ~/.codex/ which contains ChatGPT/Codex session data.
Sessions are stored as JSONL files under ~/.codex/sessions/YYYY/MM/DD/ with
metadata in ~/.codex/session_index.jsonl and databases for goals, logs, and memories.
"""

import json
import os
import time
from pathlib import Path
from typing import Optional

from .schema import get_db, init_db


CODEX_DIR = Path.home() / ".codex"
CODEX_SESSIONS_DIR = CODEX_DIR / "sessions"
CODEX_INDEX = CODEX_DIR / "session_index.jsonl"


def import_codex(batch_id: str, since: Optional[float] = None) -> dict:
    """
    Import Codex sessions from ~/.codex/ into the journal.

    Structure:
      ~/.codex/session_index.jsonl — One JSON per line: {id, thread_name, updated_at}
      ~/.codex/sessions/YYYY/MM/DD/rollout-<timestamp>-<id>.jsonl — Full session JSONL
      Each JSONL line has a "type" field: session_meta, event_msg, response_item, etc.
    """
    if not CODEX_DIR.exists():
        return {"source": "codex", "imported_conversations": 0, "imported_messages": 0, "skipped": True, "reason": f"{CODEX_DIR} not found"}

    jdb = init_db()
    conv_imported = 0
    msg_imported = 0

    # Build index from session_index.jsonl
    index = {}
    if CODEX_INDEX.exists():
        try:
            with open(CODEX_INDEX) as f:
                for line in f:
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        entry = json.loads(line)
                        session_id = entry.get("id", "")
                        index[session_id] = {
                            "title": entry.get("thread_name", ""),
                            "updated_at": entry.get("updated_at", ""),
                        }
                    except json.JSONDecodeError:
                        continue
        except Exception:
            pass

    # Walk the date-organized session directories
    if CODEX_SESSIONS_DIR.exists():
        for jsonl_file in sorted(CODEX_SESSIONS_DIR.rglob("*.jsonl")):
            # Extract session_id from filename: rollout-2026-07-18T12-08-46-019f76a1-8af1-7851-beef-168972204958.jsonl
            filename = jsonl_file.stem
            # The UUID is the last part after the final hyphen-separated timestamp
            parts = filename.split("-")
            # Find the session UUID (format: 8-4-4-4-12)
            session_id = ""
            for i in range(len(parts) - 1, -1, -1):
                candidate = "-".join(parts[i:])
                if len(candidate) >= 36:
                    session_id = candidate
                    break

            if not session_id:
                # Fallback: use the whole filename as ID
                session_id = filename

            # Check if already imported
            existing = jdb.execute(
                "SELECT id FROM conversations WHERE source = 'codex' AND session_id = ?",
                (session_id,),
            ).fetchone()

            if existing:
                continue

            # Parse the JSONL file
            messages = []
            title = index.get(session_id, {}).get("title", "")
            model = ""
            created_at = None
            workspace = ""

            try:
                with open(jsonl_file) as f:
                    for line_num, line in enumerate(f):
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            entry = json.loads(line)
                        except json.JSONDecodeError:
                            continue

                        entry_type = entry.get("type", "")

                        # Extract metadata from session_meta
                        if entry_type == "session_meta":
                            payload = entry.get("payload", {})
                            if not title:
                                title = payload.get("thread_name", "")
                            workspace = payload.get("cwd", workspace)
                            created_at = entry.get("timestamp")
                            model = payload.get("model_provider", "")
                            continue

                        # Extract user and assistant messages
                        if entry_type == "response_item":
                            payload = entry.get("payload", {})
                            role = payload.get("role", "")
                            content = payload.get("content", "")

                            if isinstance(content, list):
                                text_parts = []
                                for block in content:
                                    if isinstance(block, dict):
                                        if block.get("type") == "input_text":
                                            text_parts.append(block.get("text", ""))
                                        elif block.get("type") == "text":
                                            text_parts.append(block.get("text", ""))
                                        elif block.get("type") == "output_text":
                                            text_parts.append(block.get("text", ""))
                                content = "\n".join(text_parts)
                            elif not isinstance(content, str):
                                content = str(content)

                            if not title and role == "user" and content:
                                title = content[:200]

                            messages.append({
                                "role": role,
                                "content": content,
                                "timestamp": entry.get("timestamp"),
                                "model": model,
                            })

                        # Also capture event_msg (task events)
                        elif entry_type == "event_msg":
                            payload = entry.get("payload", {})
                            event_type = payload.get("type", "")
                            if event_type == "task_started":
                                ts = payload.get("started_at")
                                if ts and not created_at:
                                    created_at = ts

            except Exception:
                continue

            if not messages and not title:
                continue

            if not title:
                title = index.get(session_id, {}).get("title", f"Codex Session {session_id[:8]}")

            # Parse timestamp
            if isinstance(created_at, str):
                try:
                    created_at = time.mktime(time.strptime(created_at[:19], "%Y-%m-%dT%H:%M:%S"))
                except (ValueError, OverflowError):
                    created_at = jsonl_file.stat().st_mtime
            elif not created_at:
                created_at = jsonl_file.stat().st_mtime

            # Insert conversation
            jdb.execute(
                """INSERT OR IGNORE INTO conversations
                   (source, session_id, title, model, workspace, created_at, updated_at,
                    message_count, source_path, import_batch, import_ts, metadata)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    "codex",
                    session_id,
                    title,
                    model,
                    workspace,
                    created_at,
                    jsonl_file.stat().st_mtime,
                    len(messages),
                    str(jsonl_file),
                    batch_id,
                    time.time(),
                    json.dumps({"index_meta": index.get(session_id, {})}),
                ),
            )
            conv_id = jdb.execute("SELECT last_insert_rowid()").fetchone()[0]

            if conv_id == 0:
                row = jdb.execute(
                    "SELECT id FROM conversations WHERE source = 'codex' AND session_id = ?",
                    (session_id,),
                ).fetchone()
                if not row:
                    continue
                conv_id = row["id"]

            # Insert messages
            for seq, msg in enumerate(messages):
                ts = msg.get("timestamp")
                if isinstance(ts, str):
                    try:
                        ts = time.mktime(time.strptime(ts[:19], "%Y-%m-%dT%H:%M:%S"))
                    except (ValueError, OverflowError):
                        ts = None

                jdb.execute(
                    """INSERT INTO messages
                       (conversation_id, seq, role, content, timestamp, model, metadata)
                       VALUES (?, ?, ?, ?, ?, ?, ?)""",
                    (
                        conv_id,
                        seq,
                        msg["role"],
                        (msg["content"] or "")[:100000],
                        ts,
                        msg.get("model", ""),
                        json.dumps({}),
                    ),
                )
                msg_imported += 1

            conv_imported += 1

    jdb.commit()
    return {
        "source": "codex",
        "imported_conversations": conv_imported,
        "imported_messages": msg_imported,
        "skipped": False,
    }