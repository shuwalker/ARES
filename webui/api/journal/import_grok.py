"""
ARES Journal — Grok exporter importer.

Reads the Grok Conversation Export format and imports into the journal.

The export directory structure:
  Grok-Conversation-Export-<date>/
    INDEX.md                    — Table of contents
    <session-title>_<id>.md     — Markdown rendering of each session
    raw/<session-id>/
      chat_history.jsonl         — Full message content (JSONL)
      updates.jsonl              — Message edits/updates
      summary.json               — Session metadata
      signals.json               — Reaction/bookmark signals
"""

import json
import os
import time
from pathlib import Path
from typing import Optional

from .schema import get_db, init_db


def find_grok_exports() -> list[Path]:
    """Find Grok export directories on Desktop and in common locations."""
    search_paths = [
        Path.home() / "Desktop",
        Path.home() / "Downloads",
        Path.home() / "Documents",
    ]
    exports = []
    for search_path in search_paths:
        if search_path.exists():
            for d in search_path.iterdir():
                if d.is_dir() and d.name.startswith("Grok-Conversation-Export"):
                    if (d / "INDEX.md").exists() or (d / "raw").is_dir():
                        exports.append(d)
    return exports


def import_grok(batch_id: str, export_dir: Optional[str] = None, since: Optional[float] = None) -> dict:
    """
    Import Grok conversations from the export directory into the journal.

    Args:
        batch_id: UUID for this import run.
        export_dir: Path to the Grok export directory. If None, auto-detects.
        since: Optional unix timestamp to only import sessions after this time.
    """
    jdb = init_db()

    if export_dir:
        export_path = Path(export_dir)
    else:
        exports = find_grok_exports()
        if not exports:
            return {"source": "grok", "imported_conversations": 0, "imported_messages": 0, "skipped": True, "reason": "No Grok export found"}
        export_path = exports[0]  # Use most recent

    if not export_path.exists():
        return {"source": "grok", "imported_conversations": 0, "imported_messages": 0, "skipped": True, "reason": f"{export_path} not found"}

    conv_imported = 0
    msg_imported = 0

    # Find all raw session directories
    raw_dir = export_path / "raw"
    if not raw_dir.is_dir():
        return {"source": "grok", "imported_conversations": 0, "imported_messages": 0, "skipped": True, "reason": "No raw/ directory in export"}

    for session_dir in sorted(raw_dir.iterdir()):
        if not session_dir.is_dir():
            continue

        session_id = session_dir.name

        # Check if already imported
        existing = jdb.execute(
            "SELECT id FROM conversations WHERE source = 'grok' AND session_id = ?",
            (session_id,),
        ).fetchone()

        if existing:
            continue

        # Read summary.json for metadata
        summary_file = session_dir / "summary.json"
        title = ""
        model = ""
        created_at = None

        if summary_file.exists():
            try:
                with open(summary_file) as f:
                    summary = json.load(f)
                title = summary.get("title", "")
                model = summary.get("model", "")
                created_at = summary.get("created_at") or summary.get("start_time")
                if isinstance(created_at, str):
                    try:
                        created_at = time.mktime(time.strptime(created_at[:19], "%Y-%m-%dT%H:%M:%S"))
                    except (ValueError, OverflowError):
                        created_at = None
            except Exception:
                pass

        # Read chat_history.jsonl for messages
        chat_file = session_dir / "chat_history.jsonl"
        messages = []

        if chat_file.exists():
            try:
                with open(chat_file) as f:
                    for line in f:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            entry = json.loads(line)
                        except json.JSONDecodeError:
                            continue

                        role = entry.get("role", "")
                        content = entry.get("content", "")

                        # Handle structured content
                        if isinstance(content, list):
                            text_parts = []
                            for block in content:
                                if isinstance(block, dict):
                                    if block.get("type") == "text":
                                        text_parts.append(block.get("text", ""))
                            content = "\n".join(text_parts)
                        elif not isinstance(content, str):
                            content = str(content)

                        # Extract title from first user message
                        if role == "user" and not title and content:
                            title = content[:200]

                        messages.append({
                            "role": role,
                            "content": content,
                            "timestamp": entry.get("timestamp") or entry.get("created_at"),
                            "model": entry.get("model", ""),
                        })
            except Exception:
                pass

        if not messages and not title:
            continue

        # Fallback title
        if not title:
            title = f"Grok Session {session_id[:8]}"

        # Use directory modification time as fallback
        if not created_at:
            created_at = session_dir.stat().st_mtime

        # Insert conversation
        jdb.execute(
            """INSERT OR IGNORE INTO conversations
               (source, session_id, title, model, workspace, created_at, updated_at,
                message_count, source_path, import_batch, import_ts, metadata)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                "grok",
                session_id,
                title,
                model,
                "",
                created_at,
                session_dir.stat().st_mtime,
                len(messages),
                str(session_dir),
                batch_id,
                time.time(),
                json.dumps({"export_dir": str(export_path)}),
            ),
        )
        conv_id = jdb.execute("SELECT last_insert_rowid()").fetchone()[0]

        if conv_id == 0:
            row = jdb.execute(
                "SELECT id FROM conversations WHERE source = 'grok' AND session_id = ?",
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
        "source": "grok",
        "imported_conversations": conv_imported,
        "imported_messages": msg_imported,
        "export_dir": str(export_path),
        "skipped": False,
    }