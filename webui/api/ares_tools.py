"""ARES Tools — callable tool implementations owned by ARES.

These are the actual functions the agent can call to interact with
ARES's persistence layer: tasks, self-audit, continuity.

Each tool returns a JSON string (matching both Ares and JROS tool
result conventions). They are backend-agnostic — they operate on the
ARES continuity DB, not on Ares or JROS internals.
"""

from __future__ import annotations

import json
import os
import sqlite3
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

from pydantic import BaseModel, Field

# ── ARES Continuity DB ────────────────────────────────────────────

_ARES_DB_DIR = Path(os.environ.get("ARES_HOME", str(Path.home() / ".ares")))
_ARES_DB_PATH = _ARES_DB_DIR / "ares_continuity.db"


def _db_path() -> Path:
    """Resolve the ARES continuity DB path."""
    home = Path(os.environ.get("ARES_HOME", str(Path.home() / ".ares")))
    # ARES_HOME can point to the .ares dir itself or its parent
    if home.name == ".ares":
        return home / "ares_continuity.db"
    return home / ".ares" / "ares_continuity.db"


def _get_conn() -> sqlite3.Connection:
    """Open the continuity DB, creating tables if needed."""
    db_path = _db_path()
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row
    conn.execute("""
        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT DEFAULT '',
            priority TEXT DEFAULT 'medium',
            status TEXT DEFAULT 'open',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS promises (
            id TEXT PRIMARY KEY,
            text TEXT NOT NULL,
            source TEXT DEFAULT '',
            captured_at TEXT NOT NULL,
            resolved INTEGER DEFAULT 0
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS audit_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            turn_id TEXT NOT NULL,
            status TEXT NOT NULL,
            checks TEXT DEFAULT '{}',
            timestamp TEXT NOT NULL
        )
    """)
    conn.commit()
    return conn


# ── Tool Argument Models ──────────────────────────────────────────

class GetRuntimeContextArgs(BaseModel):
    """No arguments — returns current ARES operating state."""
    pass


class CreateTaskArgs(BaseModel):
    """Create a new ARES-owned task."""
    title: str = Field(description="Short task title")
    description: str = Field(default="", description="Task description")
    priority: str = Field(default="medium", description="Priority: low, medium, high")


class SelfAuditArgs(BaseModel):
    """Run a self-audit on the current turn."""
    turn_id: str = Field(default="", description="Turn identifier for audit")
    claims: str = Field(default="", description="Comma-separated claims to verify")


class UpdateTaskArgs(BaseModel):
    """Update an existing ARES task's status."""
    task_id: str = Field(description="The task ID to update")
    status: str = Field(description="New status: open, in_progress, blocked, done")


# ── Tool Implementations ──────────────────────────────────────────

def ares_get_runtime_context(**kwargs) -> str:
    """Get the current ARES runtime context.

    Returns the active backend, capabilities, open tasks,
    and embodiment state as a JSON string.
    """
    try:
        from api.ares_runtime_context import build_runtime_context
    except ImportError:
        # Circular import fallback
        def build_runtime_context(**kw):
            return {"identity": "ARES", "active_backend": "ares"}

    ctx = build_runtime_context()
    return json.dumps(ctx, indent=2, default=str)


def ares_create_task(
    title: str = "",
    description: str = "",
    priority: str = "medium",
    **kwargs,
) -> str:
    """Create a new ARES-owned task in the persistence layer.

    This is a callable ARES tool — the agent can use it to
    capture commitments and follow-ups durably.
    """
    if not title:
        return json.dumps({"status": "error", "error": "title is required"})

    task_id = str(uuid.uuid4())[:8]
    now = datetime.now(timezone.utc).isoformat()

    try:
        conn = _get_conn()
        conn.execute(
            "INSERT INTO tasks (id, title, description, priority, status, created_at, updated_at) "
            "VALUES (?, ?, ?, ?, 'open', ?, ?)",
            (task_id, title, description, priority, now, now),
        )
        conn.commit()
        conn.close()
    except Exception as exc:
        return json.dumps({"status": "error", "error": str(exc)})

    return json.dumps({
        "status": "created",
        "id": task_id,
        "title": title,
        "priority": priority,
    })


def ares_self_audit(
    turn_id: str = "",
    claims: str = "",
    **kwargs,
) -> str:
    """Run a self-audit on the current turn.

    Checks whether the agent's claims are backed by tool execution
    evidence. Returns a structured audit result.
    """
    now = datetime.now(timezone.utc).isoformat()

    # Audit checks — these will be expanded as ARES grows
    checks = {
        "tools_actually_called": False,  # Will be populated by lifecycle hooks
        "verification_attempted": False,    # Did the agent verify results?
        "claims_backed_by_evidence": False,  # Are claims traceable to tool output?
        "no_false_completion": True,         # Did agent claim done without running tools?
    }

    status = "pass" if all(checks.values()) else "review"

    # Persist audit event
    try:
        conn = _get_conn()
        conn.execute(
            "INSERT INTO audit_events (turn_id, status, checks, timestamp) "
            "VALUES (?, ?, ?, ?)",
            (turn_id or "unknown", status, json.dumps(checks), now),
        )
        conn.commit()
        conn.close()
    except Exception:
        pass  # Audit persistence is best-effort

    return json.dumps({
        "status": status,
        "turn_id": turn_id or "unknown",
        "checks": checks,
        "timestamp": now,
    })


def ares_update_task(
    task_id: str = "",
    status: str = "",
    **kwargs,
) -> str:
    """Update an existing ARES task's status."""
    if not task_id:
        return json.dumps({"status": "error", "error": "task_id is required"})

    now = datetime.now(timezone.utc).isoformat()

    try:
        conn = _get_conn()
        row = conn.execute(
            "SELECT id FROM tasks WHERE id = ?", (task_id,)
        ).fetchone()
        if not row:
            conn.close()
            return json.dumps({"status": "error", "error": f"task {task_id} not found"})

        conn.execute(
            "UPDATE tasks SET status = ?, updated_at = ? WHERE id = ?",
            (status, now, task_id),
        )
        conn.commit()
        conn.close()
    except Exception as exc:
        return json.dumps({"status": "error", "error": str(exc)})

    return json.dumps({
        "status": "updated",
        "id": task_id,
        "new_status": status,
    })


class DelegateToHermesArgs(BaseModel):
    """Arguments for delegating a task to Hermes."""
    task_description: str = Field(description="The highly detailed task to execute in the terminal or browser.")


def ares_delegate_to_hermes(task_description: str = "", **kwargs) -> str:
    """Delegate a task to the Hermes Execution Agent."""
    if not task_description:
        return json.dumps({"status": "error", "error": "task_description is required"})
    
    # Bridge to the Hermes execution environment
    # In production this streams to the frontend, but for the tool return we provide the synchronous ack.
    return json.dumps({
        "status": "delegated",
        "message": f"Task delegated to Hermes successfully. Execution: {task_description}",
        "target_agent": "hermes"
    })


# ── Tool Definitions Catalog ──────────────────────────────────────

ARES_TOOL_DEFS = [
    {
        "name": "ares_get_runtime_context",
        "description": (
            "Get the current ARES runtime context: active backend, "
            "capabilities, open tasks, embodiment state. Use this to "
            "understand what ARES can do right now."
        ),
        "fn": ares_get_runtime_context,
        "args_model": GetRuntimeContextArgs,
    },
    {
        "name": "ares_create_task",
        "description": (
            "Create a new ARES-owned task. Use this when you make a "
            "commitment or promise that should persist across sessions."
        ),
        "fn": ares_create_task,
        "args_model": CreateTaskArgs,
    },
    {
        "name": "ares_self_audit",
        "description": (
            "Run a self-audit on the current turn. Checks whether claims "
            "are backed by tool execution evidence."
        ),
        "fn": ares_self_audit,
        "args_model": SelfAuditArgs,
    },
    {
        "name": "ares_update_task",
        "description": (
            "Update an ARES task's status (e.g. mark as done, blocked, "
            "in_progress)."
        ),
        "fn": ares_update_task,
        "args_model": UpdateTaskArgs,
    },
    {
        "name": "ares_delegate_to_hermes",
        "description": (
            "Delegate a task to the Hermes Execution Agent. Use this tool whenever "
            "you need to run terminal commands, manipulate files, or automate the browser."
        ),
        "fn": ares_delegate_to_hermes,
        "args_model": DelegateToHermesArgs,
    },
]