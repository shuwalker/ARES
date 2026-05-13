"""Unit test for GET /api/cognitive/status.

Runs FastAPI's TestClient against the real app with SERVICES patched to []
so lifespan doesn't try to spawn the MCP / bridge subprocesses.
"""

import pytest


@pytest.fixture
def api_client(monkeypatch):
    fastapi = pytest.importorskip("fastapi")
    pytest.importorskip("fastapi.testclient")

    # Prevent lifespan from spawning subprocesses.
    monkeypatch.setattr("ares.api.SERVICES", [])

    # Build a fresh app so the lifespan reads the patched SERVICES list.
    from ares.api import create_app
    from fastapi.testclient import TestClient

    app = create_app()
    with TestClient(app) as client:
        yield client


def test_status_returns_idle_snapshot_when_loop_not_started(api_client, monkeypatch):
    # No loop instance — endpoint should still return a well-formed snapshot.
    monkeypatch.setattr("ares.api._cognitive_loop", None)

    resp = api_client.get("/api/cognitive/status")
    assert resp.status_code == 200
    body = resp.json()

    assert body["schema_version"] == 1
    assert body["running"] is False
    assert body["loop"]["cycle"] == 0
    assert body["loop"]["phase"] == "idle"
    assert body["loop"]["budget_remaining"] == 1.0
    assert body["errors"] == []
    assert body["thought"] is None
    assert "timestamp" in body


def test_status_reflects_running_loop(api_client, monkeypatch):
    from ares.core.cognitive import CognitiveLoop, Phase
    from ares.core.personality import DEFAULT_PROFILE

    loop = CognitiveLoop(personality=DEFAULT_PROFILE, max_cycles=10)
    loop.state.cycle = 7
    loop.state.phase = Phase.THINK
    loop.state.budget_remaining = 0.42
    loop._running = True

    monkeypatch.setattr("ares.api._cognitive_loop", loop)

    body = api_client.get("/api/cognitive/status").json()
    assert body["running"] is True
    assert body["loop"]["cycle"] == 7
    assert body["loop"]["phase"] == "think"
    assert body["loop"]["budget_remaining"] == 0.42
