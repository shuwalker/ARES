"""ARES Organizer — task capture, planning, and daily management.

Core personal organizer: capture obligations, turn them into realistic plans,
manage the current day, replan when circumstances change, and persist across restarts.

Tasks are stored in a per-profile JSON file: {ARES_HOME}/webui_state/tasks.json
"""

from __future__ import annotations

import json
import logging
from datetime import datetime, date, timedelta
from pathlib import Path
from typing import Any
from dataclasses import dataclass, asdict, field
from enum import Enum

logger = logging.getLogger(__name__)


class TaskStatus(str, Enum):
    """Task completion state."""
    INBOX = "inbox"          # Unprocessed capture
    TODO = "todo"            # In active task list
    BLOCKED = "blocked"      # Waiting for something else
    DONE = "done"            # Completed
    CANCELLED = "cancelled"  # Cancelled, won't do
    DEFERRED = "deferred"    # Moved to future date


class TaskPriority(str, Enum):
    """Task priority relative to the day."""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"


@dataclass
class Task:
    """A user task or commitment."""
    id: str                                  # UUID
    title: str                               # Short description
    status: TaskStatus = TaskStatus.TODO     # Current state
    priority: TaskPriority = TaskPriority.MEDIUM
    due_date: date | None = None             # When it's due
    estimated_minutes: int | None = None     # How long it takes
    project: str = ""                        # Group/project name
    context: str = ""                        # Location, person, tool required
    notes: str = ""                          # Extended notes
    created_at: datetime = field(default_factory=datetime.now)
    updated_at: datetime = field(default_factory=datetime.now)

    def to_dict(self) -> dict[str, Any]:
        """Serialize to JSON-compatible dict."""
        d = asdict(self)
        d['status'] = self.status.value
        d['priority'] = self.priority.value
        d['due_date'] = self.due_date.isoformat() if self.due_date else None
        d['created_at'] = self.created_at.isoformat()
        d['updated_at'] = self.updated_at.isoformat()
        return d

    @staticmethod
    def from_dict(d: dict[str, Any]) -> Task:
        """Deserialize from JSON dict."""
        d = dict(d)  # Copy so we don't mutate input
        d['status'] = TaskStatus(d.get('status', 'todo'))
        d['priority'] = TaskPriority(d.get('priority', 'medium'))
        d['due_date'] = date.fromisoformat(d['due_date']) if d.get('due_date') else None
        d['created_at'] = datetime.fromisoformat(d['created_at']) if d.get('created_at') else datetime.now()
        d['updated_at'] = datetime.fromisoformat(d['updated_at']) if d.get('updated_at') else datetime.now()
        return Task(**d)


def _tasks_file() -> Path:
    """Return the tasks.json path for the active profile."""
    from api.config import STATE_DIR
    return STATE_DIR / 'tasks.json'


def _load_tasks() -> list[Task]:
    """Load all tasks from disk."""
    path = _tasks_file()
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding='utf-8'))
        return [Task.from_dict(t) for t in (data.get('tasks', []) if isinstance(data, dict) else data or [])]
    except Exception as exc:
        logger.warning(f"Failed to load tasks from {path}: {exc}")
        return []


def _save_tasks(tasks: list[Task]) -> None:
    """Save all tasks to disk."""
    path = _tasks_file()
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(
            json.dumps({'tasks': [t.to_dict() for t in tasks]}, indent=2, default=str),
            encoding='utf-8'
        )
    except Exception as exc:
        logger.error(f"Failed to save tasks to {path}: {exc}")


def create_task(
    title: str,
    status: str = "todo",
    priority: str = "medium",
    due_date: str | None = None,
    estimated_minutes: int | None = None,
    project: str = "",
    context: str = "",
    notes: str = "",
) -> dict[str, Any]:
    """Create a new task and save it."""
    import uuid
    task = Task(
        id=str(uuid.uuid4()),
        title=title,
        status=TaskStatus(status),
        priority=TaskPriority(priority),
        due_date=date.fromisoformat(due_date) if due_date else None,
        estimated_minutes=estimated_minutes,
        project=project,
        context=context,
        notes=notes,
    )
    tasks = _load_tasks()
    tasks.append(task)
    _save_tasks(tasks)
    logger.info(f"Created task: {task.id} — {title}")
    return task.to_dict()


def list_tasks(status: str | None = None) -> list[dict[str, Any]]:
    """List all tasks, optionally filtered by status."""
    tasks = _load_tasks()
    if status:
        tasks = [t for t in tasks if t.status.value == status]
    return [t.to_dict() for t in tasks]


def get_task(task_id: str) -> dict[str, Any] | None:
    """Get a single task by ID."""
    tasks = _load_tasks()
    for t in tasks:
        if t.id == task_id:
            return t.to_dict()
    return None


def update_task(task_id: str, **updates) -> dict[str, Any] | None:
    """Update a task's fields and save."""
    tasks = _load_tasks()
    for i, t in enumerate(tasks):
        if t.id == task_id:
            # Update allowed fields
            if 'title' in updates:
                t.title = str(updates['title'])
            if 'status' in updates:
                t.status = TaskStatus(updates['status'])
            if 'priority' in updates:
                t.priority = TaskPriority(updates['priority'])
            if 'due_date' in updates:
                t.due_date = date.fromisoformat(updates['due_date']) if updates['due_date'] else None
            if 'estimated_minutes' in updates:
                t.estimated_minutes = updates.get('estimated_minutes')
            if 'project' in updates:
                t.project = str(updates['project'])
            if 'context' in updates:
                t.context = str(updates['context'])
            if 'notes' in updates:
                t.notes = str(updates['notes'])
            t.updated_at = datetime.now()
            tasks[i] = t
            _save_tasks(tasks)
            logger.info(f"Updated task: {task_id}")
            return t.to_dict()
    return None


def delete_task(task_id: str) -> bool:
    """Delete a task."""
    tasks = _load_tasks()
    original_len = len(tasks)
    tasks = [t for t in tasks if t.id != task_id]
    if len(tasks) < original_len:
        _save_tasks(tasks)
        logger.info(f"Deleted task: {task_id}")
        return True
    return False


def capture_from_conversation(text: str) -> dict[str, Any]:
    """Quick-capture a task from conversational input.

    This is a simple implementation that creates a task in the Inbox.
    A full implementation would use an LLM to extract fields.
    """
    # For MVP: just create a task with the text as title, mark as inbox
    task = Task(
        id=__import__('uuid').uuid4().hex[:8],
        title=text,
        status=TaskStatus.INBOX,
        priority=TaskPriority.MEDIUM,
    )
    tasks = _load_tasks()
    tasks.append(task)
    _save_tasks(tasks)
    logger.info(f"Captured task to inbox: {task.id} — {text}")
    return task.to_dict()


def get_today_tasks() -> dict[str, Any]:
    """Get tasks relevant for today's plan.

    Returns: {
      "now": [tasks],          # In progress or starting now
      "next": [tasks],         # Next 2 hours
      "later": [tasks],        # Later today
      "blocked": [tasks],      # Waiting for something
      "unscheduled": [tasks],  # No due date but relevant
    }
    """
    tasks = _load_tasks()
    today = date.today()

    now = []
    next_2h = []
    later = []
    blocked = []
    unscheduled = []

    for t in tasks:
        # Skip completed/cancelled/deferred
        if t.status in (TaskStatus.DONE, TaskStatus.CANCELLED, TaskStatus.DEFERRED):
            continue

        if t.status == TaskStatus.BLOCKED:
            blocked.append(t)
        elif t.due_date == today:
            # Due today
            if t.priority == TaskPriority.HIGH:
                now.append(t)
            else:
                next_2h.append(t)
        elif t.due_date is None and t.status == TaskStatus.TODO:
            # Unscheduled
            unscheduled.append(t)

    # Sort by priority
    for lst in (now, next_2h, blocked, unscheduled):
        lst.sort(key=lambda t: (
            0 if t.priority == TaskPriority.HIGH else (1 if t.priority == TaskPriority.MEDIUM else 2),
            t.created_at
        ))

    return {
        "now": [t.to_dict() for t in now],
        "next": [t.to_dict() for t in next_2h],
        "later": [t.to_dict() for t in later],
        "blocked": [t.to_dict() for t in blocked],
        "unscheduled": [t.to_dict() for t in unscheduled],
    }


def generate_daily_plan() -> dict[str, Any]:
    """Generate a simple daily plan from today's tasks.

    Returns: {
      "plan": [{"task_id": "...", "start_time": "09:00", "duration_minutes": 30}, ...],
      "summary": "...",  # Human-readable plan description
    }
    """
    today_tasks = get_today_tasks()
    all_tasks = [
        Task.from_dict(task_dict)
        for task_list in today_tasks.values()
        for task_dict in task_list
    ]

    # Simple time-blocking: allocate tasks across the day (9am-5pm = 480 minutes)
    # High priority = now, Medium = spread throughout, Low = if time permits
    plan = []
    current_time = 9 * 60  # 9:00 AM in minutes since midnight
    end_time = 17 * 60      # 5:00 PM

    # Order: now → next → unscheduled (medium/high priority) → later
    high_priority = [t for t in all_tasks if t.priority == TaskPriority.HIGH]
    medium_priority = [t for t in all_tasks if t.priority == TaskPriority.MEDIUM]
    low_priority = [t for t in all_tasks if t.priority == TaskPriority.LOW]

    for task in high_priority + medium_priority + low_priority:
        duration = task.estimated_minutes or 30  # Default 30 min
        if current_time + duration <= end_time:
            plan.append({
                "task_id": task.id,
                "task_title": task.title,
                "start_time": f"{current_time // 60:02d}:{current_time % 60:02d}",
                "duration_minutes": duration,
            })
            current_time += duration

    return {
        "plan": plan,
        "summary": f"Today: {len(plan)} tasks scheduled, {len(all_tasks) - len(plan)} unscheduled",
        "generated_at": datetime.now().isoformat(),
    }
