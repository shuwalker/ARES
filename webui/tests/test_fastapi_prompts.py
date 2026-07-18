"""Contract tests for profile-scoped saved prompts."""

from __future__ import annotations

import asyncio
from pathlib import Path

import httpx
import pytest

from fastapi_app.main import create_app
from fastapi_app.request_context import RequestIdentity, require_identity, require_mutation_identity


IDENTITY = RequestIdentity(session_cookie=None, profile="default", auth_enabled=False)


def request(app, method: str, path: str, **kwargs) -> httpx.Response:
    async def run() -> httpx.Response:
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as client:
            return await client.request(method, path, **kwargs)

    return asyncio.run(run())


@pytest.fixture
def app(tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
    frontend = tmp_path / "dist"
    frontend.mkdir()
    (frontend / "index.html").write_text("<div id='root'></div>", encoding="utf-8")
    monkeypatch.setattr("api.saved_prompts.saved_prompts_path", lambda: tmp_path / "prompts.json")
    application = create_app(frontend_root=frontend)
    application.dependency_overrides[require_identity] = lambda: IDENTITY
    application.dependency_overrides[require_mutation_identity] = lambda: IDENTITY
    return application


def test_saved_prompt_round_trip_preserves_legacy_shape(app):
    created = request(app, "POST", "/api/prompts", json={"text": "  Review this  ", "label": ""})
    listed = request(app, "GET", "/api/prompts")

    assert created.status_code == 200
    assert created.json()["prompt"]["label"] == "Review this"
    assert created.json()["prompt"]["text"] == "Review this"
    assert listed.json()["prompts"] == [created.json()["prompt"]]

    deleted = request(app, "DELETE", "/api/prompts", json={"id": created.json()["prompt"]["id"]})
    assert deleted.json() == {"ok": True}
    assert request(app, "GET", "/api/prompts").json() == {"prompts": []}


def test_saved_prompt_validation_is_bounded_and_typed(app):
    blank = request(app, "POST", "/api/prompts", json={"text": " "})
    too_long = request(app, "POST", "/api/prompts", json={"text": "x" * 8_001})
    missing_id = request(app, "DELETE", "/api/prompts", json={})

    assert blank.status_code == 400
    assert blank.json() == {"error": "text is required"}
    assert too_long.status_code == 400
    assert missing_id.status_code == 400
