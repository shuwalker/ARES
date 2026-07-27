"""Task-delegation launcher: create -> run on backend -> terminal Run status."""

from __future__ import annotations

import importlib
import sys
import time
from pathlib import Path

import pytest

WEBUI = Path(__file__).resolve().parents[1]
if str(WEBUI) not in sys.path:
    sys.path.insert(0, str(WEBUI))


@pytest.fixture
def tasks_mod(tmp_path, monkeypatch):
    """delegation_tasks bound to an isolated ARES_HOME."""
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    from api import delegation_tasks

    importlib.reload(delegation_tasks)
    return delegation_tasks


def test_create_task_is_queued(tasks_mod):
    task = tasks_mod.create_task(prompt="hello", backend="hermes_local")
    assert task["status"] == tasks_mod.STATUS_QUEUED
    assert task["id"]
    assert tasks_mod.get_task(task["id"])["prompt"] == "hello"


def test_terminal_status_is_immutable(tasks_mod):
    task = tasks_mod.create_task(prompt="p", backend="b")
    tasks_mod.update_status(task["id"], tasks_mod.STATUS_COMPLETED, result="done")
    # A later transition on a terminal task is ignored.
    tasks_mod.update_status(task["id"], tasks_mod.STATUS_FAILED, error="late")
    final = tasks_mod.get_task(task["id"])
    assert final["status"] == tasks_mod.STATUS_COMPLETED
    assert final["result"] == "done"
    assert final["error"] is None


class _FakeBackend:
    def __init__(self, result):
        self._result = result

    def is_available(self):
        return True

    def run_turn(self, prompt, session_id, **kwargs):
        return self._result


class _FakeRouter:
    def __init__(self, backends):
        self.backends = backends


def _patch_router(monkeypatch, backends):
    fake = _FakeRouter(backends)
    monkeypatch.setattr("api.backends.router.get_router", lambda: fake)


def test_delegate_completes(tmp_path, monkeypatch):
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    from api import delegation_tasks, delegation_runner

    importlib.reload(delegation_tasks)
    importlib.reload(delegation_runner)

    _patch_router(monkeypatch, {"hermes_local": _FakeBackend({"text": "42", "error": None})})

    task = delegation_runner.delegate(prompt="what is 6*7", backend="hermes_local")
    result = _await_terminal(delegation_tasks, task["id"])
    assert result["status"] == delegation_tasks.STATUS_COMPLETED
    assert result["result"] == "42"


def test_delegate_failed_backend_error(tmp_path, monkeypatch):
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    from api import delegation_tasks, delegation_runner

    importlib.reload(delegation_tasks)
    importlib.reload(delegation_runner)

    _patch_router(monkeypatch, {"hermes_local": _FakeBackend({"text": "", "error": "boom"})})

    task = delegation_runner.delegate(prompt="x", backend="hermes_local")
    result = _await_terminal(delegation_tasks, task["id"])
    assert result["status"] == delegation_tasks.STATUS_FAILED
    assert result["error"] == "boom"


def test_delegate_unavailable_backend(tmp_path, monkeypatch):
    monkeypatch.setenv("ARES_HOME", str(tmp_path))
    from api import delegation_tasks, delegation_runner

    importlib.reload(delegation_tasks)
    importlib.reload(delegation_runner)

    _patch_router(monkeypatch, {})  # backend not registered

    task = delegation_runner.delegate(prompt="x", backend="ghost")
    result = _await_terminal(delegation_tasks, task["id"])
    assert result["status"] == delegation_tasks.STATUS_FAILED
    assert "unavailable" in (result["error"] or "").lower()


def _await_terminal(tasks_mod, task_id, timeout=5.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        task = tasks_mod.get_task(task_id)
        if task and tasks_mod.is_terminal(task["status"]):
            return task
        time.sleep(0.02)
    raise AssertionError(f"task {task_id} did not reach a terminal status")
