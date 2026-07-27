"""Organizer MVP tests — task capture, planning, today view."""

import json
import urllib.error
import urllib.request
from pathlib import Path

import pytest

from tests._pytest_port import BASE


def get(path):
    with urllib.request.urlopen(BASE + path, timeout=10) as r:
        return json.loads(r.read()), r.status


def post(path, body=None):
    req = urllib.request.Request(
        BASE + path,
        data=json.dumps(body or {}).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            return json.loads(r.read()), r.status
    except urllib.error.HTTPError as e:
        return json.loads(e.read()), e.code


def test_create_task():
    """Test creating a task via the organizer API."""
    data, status = post(
        "/api/organizer/tasks",
        {
            "title": "Review Q4 report",
            "priority": "high",
            "estimated_minutes": 30,
        },
    )
    assert status == 200
    assert data["title"] == "Review Q4 report"
    assert data["priority"] == "high"
    assert data["estimated_minutes"] == 30
    assert data["status"] == "todo"
    assert "id" in data


def test_list_tasks():
    """Test listing all tasks."""
    # Create a task first
    created, _ = post(
        "/api/organizer/tasks",
        {
            "title": "Test task",
            "priority": "medium",
        },
    )

    # List tasks
    data, status = get("/api/organizer/tasks")
    assert status == 200
    assert "tasks" in data
    assert isinstance(data["tasks"], list)
    assert len(data["tasks"]) > 0
    assert any(t["title"] == "Test task" for t in data["tasks"])


def test_capture_from_conversation():
    """Test quick-capturing a task from chat."""
    data, status = post(
        "/api/organizer/capture",
        {
            "text": "Remind me to renew the registration next Thursday",
        },
    )
    assert status == 200
    assert data["title"] == "Remind me to renew the registration next Thursday"
    assert data["status"] == "inbox"
    assert "id" in data


def test_get_today_tasks():
    """Test getting today's task view."""
    # Create some tasks
    post(
        "/api/organizer/tasks",
        {
            "title": "Urgent task",
            "priority": "high",
            "status": "todo",
        },
    )

    data, status = get("/api/organizer/today")
    assert status == 200
    assert "now" in data
    assert "next" in data
    assert "later" in data
    assert "blocked" in data
    assert "unscheduled" in data


def test_generate_daily_plan():
    """Test generating a daily plan."""
    data, status = get("/api/organizer/plan")
    assert status == 200
    assert "plan" in data
    assert "summary" in data
    assert "generated_at" in data
    assert isinstance(data["plan"], list)
