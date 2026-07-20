"""
ARES Journal — Claude Code importer.

Reads all JSONL session files from ~/.claude/projects/ and imports them
into the journal. Each project directory contains one or more .jsonl files,
where each line is a JSON object representing a message or tool call.
"""

import json
import os
import time
from pathlib import Path
from typing import Optional

from .schema import get_db, init_db


CLAUDE_PROJECTS_DIR = Path.home() / ".claude" / "projects"


def import_claude_code(batch_id: str, since: Optional[float] = None) -> dict:
    """
    Import all Claude Code sessions into the journal.

    Claude Code stores sessions as JSONL files under ~/.claude/projects/<project-dir>/.
    Each file is one session. Each line is a JSON object with role, content, etc.
    """
    if not CLAUDE_PROJECTS_DIR.exists():
        return {"source": "claude_code", "imported_conversations": 0, "imported_messages": 0, "skipped": True, "reason": f"{CLAUDE_PROJECTS_DIR} not found"}

    jdb = init_db()
    conv_imported = 0
    msg_imported = 0

    # Walk all project directories
    for project_dir in sorted(CLAUDE_PROJECTS_DIR.iterdir()):
        if not project_dir.is_dir():
            continue

        project_name = project_dir.name.lstrip("-").replace("-", "/")

        # Find all JSONL session files
        for jsonl_file in sorted(project_dir.glob("*.jsonl")):
            session_id = jsonl_file.stem

            # Check if already imported
            existing = jdb.execute(
                "SELECT id FROM conversations WHERE source = 'claude_code' AND session_id = ?",
                (session_id,),
            ).fetchone()

            if existing:
                continue

            # Parse the JSONL file
            messages = []
            title = ""
            model = ""
            created_at = None

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

                        role = entry.get("role", "")
                        content = entry.get("content", "")

                        # Extract text content from structured content
                        if isinstance(content, list):
                            text_parts = []
                            for block in content:
                                if isinstance(block, dict):
                                    if block.get("type") == "text":
                                        text_parts.append(block.get("text", ""))
                                    elif block.get("type") == "tool_result":
                                        text_parts.append(block.get("content", ""))
                            content = "\n".join(text_parts)
                        elif not isinstance(content, str):
                            content = str(content)

                        # Use first user message as title hint
                        if role == "user" and not title and content:
                            title = content[:200]

                        # Extract model from assistant messages
                        if role == "assistant" and entry.get("model"):
                            model = entry["model"]

                        # Use message timestamp if available
                        ts = entry.get("timestamp") or entry.get("created_at")
                        if isinstance(ts, (int, float)):
                            created_at = created_at or ts

                        messages.append({
                            "role": role,
                            "content": content,
                            "timestamp": ts,
                            "tool_name": entry.get("tool_name") or entry.get("name"),
                            "model": entry.get("model", ""),
                        })
            except Exception as e:
                continue

            if not messages:
                continue

            # Use file modification time as fallback timestamp
            if not created_at:
                created_at = jsonl_file.stat().st_mtime

            # Insert conversation
            jdb.execute(
                """INSERT OR IGNORE INTO conversations
                   (source, session_id, title, model, workspace, created_at, updated_at,
                    message_count, source_path, import_batch, import_ts, metadata)
                   VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (
                    "claude_code",
                    session_id,
                    title or f"Claude Code — {project_name}",
                    model,
                    project_name,
                    created_at,
                    jsonl_file.stat().st_mtime,
                    len(messages),
                    str(jsonl_file),
                    batch_id,
                    time.time(),
                    json.dumps({"project": project_name, "file": jsonl_file.name}),
                ),
            )
            conv_id = jdb.execute("SELECT last_insert_rowid()").fetchone()[0]

            if conv_id == 0:
                row = jdb.execute(
                    "SELECT id FROM conversations WHERE source = 'claude_code' AND session_id = ?",
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
                        ts = time.mktime(time.strptime(ts, "%Y-%m-%dT%H:%M:%S"))
                    except (ValueError, OverflowError):
                        ts = None

                jdb.execute(
                    """INSERT INTO messages
                       (conversation_id, seq, role, content, timestamp, model,
                        tool_name, metadata)
                       VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                    (
                        conv_id,
                        seq,
                        msg["role"],
                        (msg["content"] or "")[:100000],
                        ts,
                        msg.get("model", ""),
                        msg.get("tool_name"),
                        json.dumps({}),
                    ),
                )
                msg_imported += 1

            conv_imported += 1

    jdb.commit()
    return {
        "source": "claude_code",
        "imported_conversations": conv_imported,
        "imported_messages": msg_imported,
        "skipped": False,
    }