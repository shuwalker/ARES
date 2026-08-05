"""JaegerAI Companion adapter and normalized ARES API contracts."""
from __future__ import annotations

import asyncio
from pathlib import Path

import httpx
import pytest

from api.providers.jaeger import companion_control
from fastapi_app.main import create_app
from fastapi_app.request_context import RequestIdentity, require_identity, require_mutation_identity


IDENTITY = RequestIdentity(session_cookie=None, profile="default", auth_enabled=False)


class HealthOnlyService:
    def health(self, *, deep: bool = False):
        return {"status": "ok", "sessions": 0, "active_streams": 0}, 200


def _request(app, method: str, path: str, **kwargs) -> httpx.Response:
    async def run() -> httpx.Response:
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as client:
            return await client.request(method, path, **kwargs)

    return asyncio.run(run())


def test_companion_snapshot_uses_only_bridge_contract(monkeypatch: pytest.MonkeyPatch):
    replies = {
        "identity": {"agent_name": "Jarvis", "model": "local-model", "avatar": None},
        "character": {
            "id": "jarvis",
            "name": "Jarvis",
            "role": "Personal assistant",
            "voice_tone": "dry",
            "voice_id": "bm_george",
            "custom_instructions": "Be useful.",
        },
        "characters": [
            {"id": "jarvis", "name": "Jarvis", "active": True, "bound": True},
            {"id": "tars", "name": "TARS", "active": False, "bound": False},
        ],
    }
    monkeypatch.setattr(
        "api.providers.jaeger.gateway_streaming.query_local_companion",
        lambda what, args=None: replies[what],
    )
    monkeypatch.setattr("api.providers.jaeger.paths.jaeger_home", lambda: Path("/opt/JaegerAI"))
    monkeypatch.setattr("api.providers.jaeger.paths.jros_instance_name", lambda: "jarvis")

    result = companion_control.companion_snapshot()

    assert result["dependency"] == {
        "product": "JaegerAI",
        "root": "/opt/JaegerAI",
        "transport": "bridge",
    }
    assert result["agent"]["id"] == "jarvis"
    assert result["agent"]["name"] == "Jarvis"
    assert result["character"]["id"] == "jarvis"
    assert [row["id"] for row in result["characters"]] == ["jarvis", "tars"]


def test_companion_update_delegates_writes_to_jaeger(monkeypatch: pytest.MonkeyPatch):
    commands: list[tuple[str, dict]] = []
    monkeypatch.setattr(
        "api.providers.jaeger.gateway_streaming.command_local_companion",
        lambda cmd, args=None: commands.append((cmd, args or {})),
    )
    monkeypatch.setattr(
        companion_control,
        "companion_snapshot",
        lambda: {"agent": {"name": "Athena"}, "character": {"id": "tars"}},
    )

    result = companion_control.update_companion(name="Athena", character_id="tars")

    assert commands == [
        ("save_identity", {"name": "Athena"}),
        ("select_character", {"id": "tars"}),
        ("make_default", {"id": "tars"}),
    ]
    assert result["agent"]["name"] == "Athena"


def test_companion_api_reads_and_updates_one_live_identity(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
):
    frontend = tmp_path / "dist"
    frontend.mkdir()
    (frontend / "index.html").write_text("<div id='root'></div>", encoding="utf-8")
    application = create_app(frontend_root=frontend, core_service=HealthOnlyService())
    application.dependency_overrides[require_identity] = lambda: IDENTITY
    application.dependency_overrides[require_mutation_identity] = lambda: IDENTITY

    snapshot = {
        "contract_version": 1,
        "dependency": {"product": "JaegerAI", "root": "/opt/JaegerAI", "transport": "bridge"},
        "agent": {"id": "jarvis", "name": "Jarvis", "model": None, "avatar": None},
        "character": {"id": "jarvis", "name": "Jarvis"},
        "characters": [],
    }
    monkeypatch.setattr(
        "api.providers.jaeger.companion_control.companion_snapshot",
        lambda: snapshot,
    )
    monkeypatch.setattr("api.config.load_settings", lambda: {"bot_name": "Jarvis", "owner_name": "Matt"})

    response = _request(application, "GET", "/api/companion")
    assert response.status_code == 200
    assert response.json()["relationship"] == {
        "owner_name": "Matt",
        "ares_name": "Jarvis",
        "aligned": True,
    }

    saved: list[dict] = []
    runtime_saved: list[dict] = []
    changed = {**snapshot, "agent": {**snapshot["agent"], "name": "Astra"}}
    monkeypatch.setattr(
        "api.providers.jaeger.companion_control.update_companion",
        lambda **kwargs: changed,
    )
    monkeypatch.setattr("api.config.save_settings", lambda patch: saved.append(patch))
    monkeypatch.setattr(
        "fastapi_app.routers.ares.save_config_values",
        lambda patch: runtime_saved.append(patch),
    )
    monkeypatch.setattr("api.config.load_settings", lambda: {"bot_name": "Astra", "owner_name": "Matt"})

    updated = _request(application, "PATCH", "/api/companion", json={"name": "Astra"})
    assert updated.status_code == 200
    assert updated.json()["agent"]["name"] == "Astra"
    assert saved == [{"bot_name": "Astra"}]
    assert runtime_saved == [{"ares_backend": "jaeger_local"}]

    invalid = _request(application, "PATCH", "/api/companion", json={"unknown": True})
    assert invalid.status_code == 400

    blank = _request(application, "PATCH", "/api/companion", json={"name": "   "})
    assert blank.status_code == 400
