"""Contracts for Mac-owned System settings and controller lifecycle commands."""

from __future__ import annotations

import asyncio
import json
from pathlib import Path
import time

import httpx
import pytest

from api.native_system import (
    NativeSystemContractError,
    enqueue_native_action,
    native_command_path,
    native_runtime_path,
    native_system_status,
    update_native_settings,
)
from fastapi_app.main import create_app
from fastapi_app.request_context import RequestIdentity, require_identity, require_mutation_identity


IDENTITY = RequestIdentity(session_cookie=None, profile="default", auth_enabled=False)


class HealthOnlyService:
    def health(self, *, deep: bool = False):
        return {
            "status": "ok",
            "sessions": 0,
            "active_streams": 0,
            "uptime_seconds": 1.0,
        }, 200


@pytest.fixture(autouse=True)
def isolated_native_state(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("ARES_NATIVE_STATE_DIR", str(tmp_path))
    monkeypatch.setenv("ARES_RUNTIME_OWNER", "mac_app")
    monkeypatch.setenv("ARES_RUNTIME_INSTANCE_ID", "mac-instance")
    monkeypatch.setenv("ARES_WEBUI_HOST", "127.0.0.1")
    monkeypatch.setenv("ARES_WEBUI_PORT", "8788")


def write_runtime(*, instance_id: str = "mac-instance", age: float = 0.0) -> None:
    native_runtime_path().write_text(
        json.dumps(
            {
                "contract_version": 1,
                "instance_id": instance_id,
                "app_pid": 1234,
                "heartbeat_unix": time.time() - age,
                "capabilities": {
                    "menu_bar": True,
                    "launch_at_login": True,
                    "quick_launch": True,
                    "background_operation": True,
                    "server_restart": True,
                },
                "effective": {
                    "menu_bar_enabled": True,
                    "launch_at_login": False,
                    "quick_launch_enabled": True,
                    "quick_launch_shortcut": "command+shift+space",
                    "background_operation": True,
                },
            }
        ),
        encoding="utf-8",
    )


def test_status_separates_desired_effective_and_runtime_owner():
    write_runtime()

    status = native_system_status()

    assert status["native_app"]["connected"] is True
    assert status["controller"] == {
        "running": True,
        "pid": status["controller"]["pid"],
        "host": "127.0.0.1",
        "port": 8788,
        "owner": "mac_app",
        "managed_by_mac_app": True,
        "instance_id": "mac-instance",
    }
    assert status["desired"]["menu_bar_enabled"] is True
    assert status["effective"]["menu_bar_enabled"] is True
    assert status["capabilities"]["server_restart"] is True


def test_stale_or_wrong_instance_never_claims_native_control():
    write_runtime(age=10)
    assert native_system_status()["native_app"]["connected"] is False

    write_runtime(instance_id="some-other-process")
    assert native_system_status()["native_app"]["connected"] is False


def test_native_settings_and_restart_require_live_mac_owner():
    with pytest.raises(NativeSystemContractError, match="not connected"):
        update_native_settings({"menu_bar_enabled": False})
    assert not native_command_path().exists()

    write_runtime()
    updated = update_native_settings({"menu_bar_enabled": False})
    assert updated["desired"]["menu_bar_enabled"] is False
    # The native heartbeat still reports the last observed effective value.
    assert updated["effective"]["menu_bar_enabled"] is True

    accepted = enqueue_native_action("restart_server")
    command = json.loads(native_command_path().read_text(encoding="utf-8"))
    assert accepted["accepted"] is True
    assert command["action"] == "restart_server"
    assert command["instance_id"] == "mac-instance"


def _request(app, method: str, path: str, **kwargs) -> httpx.Response:
    async def run() -> httpx.Response:
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as client:
            return await client.request(method, path, **kwargs)

    return asyncio.run(run())


def test_native_system_api_is_typed_and_truthful(tmp_path: Path):
    frontend = tmp_path / "dist"
    frontend.mkdir()
    (frontend / "index.html").write_text("<div id='root'></div>", encoding="utf-8")
    application = create_app(frontend_root=frontend, core_service=HealthOnlyService())
    application.dependency_overrides[require_identity] = lambda: IDENTITY
    application.dependency_overrides[require_mutation_identity] = lambda: IDENTITY

    health = _request(application, "GET", "/health")
    assert health.status_code == 200
    assert health.json()["runtime_owner"] == "mac_app"
    assert health.json()["runtime_instance_id"] == "mac-instance"

    unavailable = _request(application, "GET", "/api/system/native")
    assert unavailable.status_code == 200
    assert unavailable.json()["native_app"]["connected"] is False

    rejected = _request(
        application,
        "PATCH",
        "/api/system/native/settings",
        json={"menu_bar_enabled": False},
    )
    assert rejected.status_code == 409
    assert "not connected" in rejected.json()["error"]

    invalid = _request(
        application,
        "PATCH",
        "/api/system/native/settings",
        json={"made_up_native_setting": True},
    )
    assert invalid.status_code == 400

    write_runtime()
    updated = _request(
        application,
        "PATCH",
        "/api/system/native/settings",
        json={"menu_bar_enabled": False},
    )
    assert updated.status_code == 200
    assert updated.json()["desired"]["menu_bar_enabled"] is False
