"""Profile-scoped durable storage for delegated tasks owned by ARES.

A delegated task is a discrete unit of work handed to an execution backend
(Hermes, Gemini/Antigravity, Ollama, a CLI backend) and awaited asynchronously.
The caller creates a task, gets an id back immediately, and polls status until
it reaches a terminal Run state. Storage mirrors `schedule_jobs.py`: an atomic
JSON file with 0600 perms under the active profile's ARES home.
"""

from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import tempfile
import threading
from typing import Any
import uuid


ARES_DIR = Path(os.environ.get("ARES_HOME", "~/.ares")).expanduser()
DELEGATION_DIR = ARES_DIR / "delegation"
TASKS_FILE = DELEGATION_DIR / "tasks.json"
_LOCK = threading.RLock()

# Run status vocabulary (FOUNDATION.md): Queued, Running, Completed, Failed,
# Canceled. "Needs input" is not modeled for one-shot delegated tasks.
STATUS_QUEUED = "queued"
STATUS_RUNNING = "running"
STATUS_COMPLETED = "completed"
STATUS_FAILED = "failed"
STATUS_CANCELED = "canceled"
_TERMINAL = frozenset({STATUS_COMPLETED, STATUS_FAILED, STATUS_CANCELED})


def _ensure_storage() -> None:
    DELEGATION_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        DELEGATION_DIR.chmod(0o700)
    except OSError:
        pass


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _read_tasks() -> list[dict[str, Any]]:
    _ensure_storage()
    if not TASKS_FILE.is_file():
        return []
    try:
        payload = json.loads(TASKS_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    rows = payload.get("tasks", []) if isinstance(payload, dict) else payload
    return [dict(row) for row in rows if isinstance(row, dict)] if isinstance(rows, list) else []


def _write_tasks(tasks: list[dict[str, Any]]) -> None:
    _ensure_storage()
    fd, temporary = tempfile.mkstemp(prefix="tasks-", suffix=".json", dir=DELEGATION_DIR)
    path = Path(temporary)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump({"tasks": tasks}, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        path.chmod(0o600)
        os.replace(path, TASKS_FILE)
        TASKS_FILE.chmod(0o600)
    finally:
        if path.exists():
            path.unlink(missing_ok=True)


def create_task(*, prompt: str, backend: str, model: str | None = None, provider: str | None = None) -> dict[str, Any]:
    """Persist a new delegated task in the Queued state and return it."""
    task = {
        "id": uuid.uuid4().hex,
        "prompt": str(prompt or ""),
        "backend": str(backend or ""),
        "model": model,
        "provider": provider,
        "status": STATUS_QUEUED,
        "result": None,
        "error": None,
        "created_at": _now(),
        "updated_at": _now(),
    }
    with _LOCK:
        tasks = _read_tasks()
        tasks.append(task)
        _write_tasks(tasks)
    return dict(task)


def get_task(task_id: str) -> dict[str, Any] | None:
    task_id = str(task_id or "").strip()
    if not task_id:
        return None
    with _LOCK:
        for task in _read_tasks():
            if task.get("id") == task_id:
                return dict(task)
    return None


def list_tasks() -> list[dict[str, Any]]:
    with _LOCK:
        return _read_tasks()


def update_status(
    task_id: str,
    status: str,
    *,
    result: str | None = None,
    error: str | None = None,
) -> dict[str, Any] | None:
    """Transition a task's Run status; ignores writes to already-terminal tasks."""
    task_id = str(task_id or "").strip()
    with _LOCK:
        tasks = _read_tasks()
        updated = None
        for task in tasks:
            if task.get("id") != task_id:
                continue
            if task.get("status") in _TERMINAL:
                return dict(task)
            task["status"] = status
            if result is not None:
                task["result"] = result
            if error is not None:
                task["error"] = error
            task["updated_at"] = _now()
            updated = dict(task)
            break
        if updated is not None:
            _write_tasks(tasks)
        return updated


def is_terminal(status: str) -> bool:
    return status in _TERMINAL
