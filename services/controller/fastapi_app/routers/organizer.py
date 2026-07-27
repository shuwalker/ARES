"""Organizer API endpoints — task capture, planning, daily management."""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query

from ..errors import CoreApiError
from ..request_context import RequestIdentity, require_identity


router = APIRouter(prefix="/api/organizer", tags=["organizer"])


@router.post("/tasks")
def create_task(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    """Create a new task."""
    from api.organizer import create_task as _create_task

    try:
        return _create_task(
            title=str(payload.get("title", "")).strip(),
            status=str(payload.get("status", "todo")).lower(),
            priority=str(payload.get("priority", "medium")).lower(),
            due_date=payload.get("due_date"),
            estimated_minutes=payload.get("estimated_minutes"),
            project=str(payload.get("project", "")).strip(),
            context=str(payload.get("context", "")).strip(),
            notes=str(payload.get("notes", "")).strip(),
        )
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except Exception as exc:
        raise CoreApiError(500, f"Failed to create task: {exc}") from exc


@router.get("/tasks")
def list_tasks(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    status: str = Query(None),
):
    """List all tasks, optionally filtered by status."""
    from api.organizer import list_tasks as _list_tasks

    try:
        return {"tasks": _list_tasks(status=status)}
    except Exception as exc:
        raise CoreApiError(500, f"Failed to list tasks: {exc}") from exc


@router.get("/tasks/{task_id}")
def get_task(
    task_id: str,
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    """Get a single task by ID."""
    from api.organizer import get_task as _get_task

    try:
        task = _get_task(task_id)
        if not task:
            raise CoreApiError(404, f"Task {task_id} not found")
        return task
    except CoreApiError:
        raise
    except Exception as exc:
        raise CoreApiError(500, f"Failed to get task: {exc}") from exc


@router.patch("/tasks/{task_id}")
def update_task(
    task_id: str,
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    """Update a task's fields."""
    from api.organizer import update_task as _update_task

    try:
        task = _update_task(task_id, **payload)
        if not task:
            raise CoreApiError(404, f"Task {task_id} not found")
        return task
    except CoreApiError:
        raise
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except Exception as exc:
        raise CoreApiError(500, f"Failed to update task: {exc}") from exc


@router.delete("/tasks/{task_id}")
def delete_task(
    task_id: str,
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    """Delete a task."""
    from api.organizer import delete_task as _delete_task

    try:
        success = _delete_task(task_id)
        if not success:
            raise CoreApiError(404, f"Task {task_id} not found")
        return {"deleted": True, "id": task_id}
    except CoreApiError:
        raise
    except Exception as exc:
        raise CoreApiError(500, f"Failed to delete task: {exc}") from exc


@router.post("/capture")
def capture_from_chat(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    """Quick-capture a task from conversational input."""
    from api.organizer import capture_from_conversation

    try:
        text = str(payload.get("text", "")).strip()
        if not text:
            raise ValueError("text is required")
        return capture_from_conversation(text)
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except Exception as exc:
        raise CoreApiError(500, f"Failed to capture task: {exc}") from exc


@router.get("/today")
def get_today_tasks(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    """Get tasks organized for today's view."""
    from api.organizer import get_today_tasks as _get_today_tasks

    try:
        return _get_today_tasks()
    except Exception as exc:
        raise CoreApiError(500, f"Failed to get today's tasks: {exc}") from exc


@router.get("/plan")
def generate_plan(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    """Generate a daily plan from today's tasks."""
    from api.organizer import generate_daily_plan

    try:
        return generate_daily_plan()
    except Exception as exc:
        raise CoreApiError(500, f"Failed to generate plan: {exc}") from exc


__all__ = ["router"]
