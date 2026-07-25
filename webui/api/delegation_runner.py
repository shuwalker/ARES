"""Execution bridge for delegated tasks.

Runs a discrete delegated task on an execution backend from the existing
registry, on a background thread, and records the result back to the task
store as a terminal Run status. OS-automation backends invoked this way still
pass through the consent gate in `AppAutomationBackend.run_turn`.
"""

from __future__ import annotations

import threading
from typing import Any

from api import delegation_tasks


def _resolve_backend(backend_id: str):
    from api.backends.router import get_router

    backend = get_router().backends.get(backend_id)
    if backend is None or not backend.is_available():
        return None
    return backend


def run_task_sync(task_id: str) -> dict[str, Any] | None:
    """Execute one delegated task to a terminal state and return it."""
    task = delegation_tasks.get_task(task_id)
    if task is None:
        return None

    backend = _resolve_backend(str(task.get("backend") or ""))
    if backend is None:
        return delegation_tasks.update_status(
            task_id,
            delegation_tasks.STATUS_FAILED,
            error=f"Backend unavailable: {task.get('backend') or '(none)'}",
        )

    delegation_tasks.update_status(task_id, delegation_tasks.STATUS_RUNNING)
    try:
        result = backend.run_turn(
            str(task.get("prompt") or ""),
            f"delegation:{task_id}",
            model=task.get("model"),
            model_provider=task.get("provider"),
        )
    except Exception as exc:
        return delegation_tasks.update_status(
            task_id,
            delegation_tasks.STATUS_FAILED,
            error=f"Delegation failed: {type(exc).__name__}",
        )

    error = str((result or {}).get("error") or "").strip()
    if error:
        return delegation_tasks.update_status(task_id, delegation_tasks.STATUS_FAILED, error=error)
    text = str((result or {}).get("text") or "")
    return delegation_tasks.update_status(task_id, delegation_tasks.STATUS_COMPLETED, result=text)


def delegate(*, prompt: str, backend: str, model: str | None = None, provider: str | None = None) -> dict[str, Any]:
    """Create a delegated task and start running it on a background thread.

    Returns the task record immediately (Queued); the caller polls status.
    """
    task = delegation_tasks.create_task(prompt=prompt, backend=backend, model=model, provider=provider)
    thread = threading.Thread(target=run_task_sync, args=(task["id"],), daemon=True)
    thread.start()
    return task
