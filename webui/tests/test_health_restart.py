"""Health route and shared gateway restart helper checks."""

import io
import subprocess
import threading

import api.gateway_restart as gateway_restart
from fastapi.testclient import TestClient

from fastapi_app.main import create_app


class MockPopen:
    def __init__(
        self,
        args,
        *,
        stdout_text="",
        stderr_text="",
        returncode=0,
        communicate_timeout=False,
        wait_timeout=False,
        env=None,
    ):
        self.args = args
        self.env = env or {}
        self.returncode = returncode
        self.stdout = io.StringIO(stdout_text)
        self.stderr = io.StringIO(stderr_text)
        self.communicate_timeout = communicate_timeout
        self.wait_timeout = wait_timeout
        self.terminated = False
        self.killed = False
        self.communicate_timeout_arg = None
        self.wait_timeout_arg = None

    def communicate(self, timeout=None):
        self.communicate_timeout_arg = timeout
        if self.communicate_timeout:
            raise subprocess.TimeoutExpired(self.args, timeout)
        return self.stdout.getvalue(), self.stderr.getvalue()

    def wait(self, timeout=None):
        self.wait_timeout_arg = timeout
        if self.wait_timeout:
            raise subprocess.TimeoutExpired(self.args, timeout)
        return self.returncode

    def terminate(self):
        self.terminated = True

    def kill(self):
        self.killed = True


class InlineThread:
    def __init__(self, *, target, args=(), daemon=None):
        self.target = target
        self.args = args
        self.daemon = daemon

    def start(self):
        self.target(*self.args)


def _call_health_restart(monkeypatch, helper_result):
    monkeypatch.setattr(gateway_restart, "restart_active_profile_gateway", lambda: dict(helper_result))
    with TestClient(create_app()) as client:
        response = client.post("/api/health/restart")
    return response.status_code, response.json()


def test_restart_active_profile_gateway_success_uses_active_profile_home(monkeypatch):
    gateway_restart._GATEWAY_RESTART_LOCK = threading.Lock()
    called = {}

    def fake_popen(args, stdout=None, stderr=None, text=True, env=None):
        called["args"] = args
        called["env"] = env
        return MockPopen(
            args,
            stdout_text="✓ Service restarted",
            returncode=0,
            env=env,
        )

    monkeypatch.setattr(gateway_restart, "get_active_ares_home", lambda: "/mock/ares/home")
    monkeypatch.setattr(gateway_restart.shutil, "which", lambda cmd: "/mock/bin/ares")
    monkeypatch.setattr(gateway_restart.subprocess, "Popen", fake_popen)

    result = gateway_restart.restart_active_profile_gateway()

    assert result["status"] == "completed"
    assert result["message"] == "Gateway service restarted successfully"
    assert called["args"] == ["/mock/bin/ares", "gateway", "restart"]
    assert called["env"]["ARES_HOME"] == "/mock/ares/home"
    assert gateway_restart._GATEWAY_RESTART_LOCK.locked() is False


def test_restart_active_profile_gateway_failure_preserves_empty_output_contract(monkeypatch):
    gateway_restart._GATEWAY_RESTART_LOCK = threading.Lock()

    monkeypatch.setattr(gateway_restart, "get_active_ares_home", lambda: "/mock/ares/home")
    monkeypatch.setattr(gateway_restart.shutil, "which", lambda cmd: "/mock/bin/ares")
    monkeypatch.setattr(
        gateway_restart.subprocess,
        "Popen",
        lambda args, stdout=None, stderr=None, text=True, env=None: MockPopen(
            args,
            returncode=7,
            env=env,
        ),
    )

    result = gateway_restart.restart_active_profile_gateway()

    assert result["status"] == "failed"
    assert result["message"] == "Restart failed: "
    assert result["returncode"] == 7
    assert gateway_restart._GATEWAY_RESTART_LOCK.locked() is False


def test_restart_active_profile_gateway_timeout_releases_lock_after_background_wait(monkeypatch):
    gateway_restart._GATEWAY_RESTART_LOCK = threading.Lock()
    proc = MockPopen(
        ["/mock/bin/ares", "gateway", "restart"],
        communicate_timeout=True,
        env={"ARES_HOME": "/mock/ares/home"},
    )

    monkeypatch.setattr(gateway_restart, "get_active_ares_home", lambda: "/mock/ares/home")
    monkeypatch.setattr(gateway_restart.shutil, "which", lambda cmd: "/mock/bin/ares")
    monkeypatch.setattr(gateway_restart.subprocess, "Popen", lambda *args, **kwargs: proc)
    monkeypatch.setattr(gateway_restart.threading, "Thread", InlineThread)

    result = gateway_restart.restart_active_profile_gateway()

    assert result["status"] == "in_progress"
    assert proc.communicate_timeout_arg == 2.0
    assert proc.wait_timeout_arg == 240.0
    assert gateway_restart._GATEWAY_RESTART_LOCK.locked() is False


def test_restart_active_profile_gateway_busy_reports_contention(monkeypatch):
    gateway_restart._GATEWAY_RESTART_LOCK = threading.Lock()
    assert gateway_restart._GATEWAY_RESTART_LOCK.acquire(blocking=False) is True

    try:
        result = gateway_restart.restart_active_profile_gateway()
    finally:
        gateway_restart._GATEWAY_RESTART_LOCK.release()

    assert result == {
        "status": "busy",
        "message": "Restart already in progress. Please wait a moment and try again.",
    }


def test_handle_health_restart_success(monkeypatch):
    status, payload = _call_health_restart(
        monkeypatch,
        {"status": "completed", "message": "Gateway service restarted successfully"},
    )
    assert status == 200
    assert payload == {"ok": True, "message": "Gateway service restarted successfully"}


def test_handle_health_restart_timeout(monkeypatch):
    status, payload = _call_health_restart(
        monkeypatch,
        {"status": "in_progress", "message": "Gateway service restart initiated (in progress)"},
    )
    assert status == 200
    assert payload == {"ok": True, "message": "Gateway service restart initiated (in progress)"}


def test_handle_health_restart_failure_preserves_empty_output_message(monkeypatch):
    status, payload = _call_health_restart(
        monkeypatch,
        {"status": "failed", "message": "Restart failed: "},
    )
    assert status == 500
    assert payload == {"ok": False, "error": "Restart failed: "}


def test_handle_health_restart_failure(monkeypatch):
    status, payload = _call_health_restart(
        monkeypatch,
        {"status": "failed", "message": "Restart failed: bad thing"},
    )
    assert status == 500
    assert payload == {"ok": False, "error": "Restart failed: bad thing"}


def test_handle_health_restart_internal_error(monkeypatch):
    status, payload = _call_health_restart(
        monkeypatch,
        {"status": "failed", "message": "Internal error running restart: OSError: bad spawn"},
    )
    assert status == 500
    assert payload == {"ok": False, "error": "Internal error running restart: OSError: bad spawn"}


def test_handle_health_restart_concurrency(monkeypatch):
    status, payload = _call_health_restart(
        monkeypatch,
        {"status": "busy", "message": "Restart already in progress. Please wait a moment and try again."},
    )
    assert status == 429
    assert payload == {
        "ok": False,
        "error": "Restart already in progress. Please wait a moment and try again.",
    }
