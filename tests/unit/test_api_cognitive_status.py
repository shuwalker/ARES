"""Unit test for GET /api/cognitive/status.

Now returns an idle snapshot since the CognitiveLoop has been replaced by
the AgentInterface backend system. The endpoint still works but always
returns running=False until a backend-driven loop is wired in.
"""

import pytest


@pytest.fixture
def api_client(monkeypatch):
    pytest.importorskip("fastapi")
    pytest.importorskip("fastapi.testclient")

    # Prevent lifespan from spawning subprocesses.
    monkeypatch.setattr("ares.api.SERVICES", [])

    from ares.api import create_app
    from fastapi.testclient import TestClient

    app = create_app()
    with TestClient(app) as client:
        yield client


def test_status_returns_idle_snapshot(api_client):
    """The cognitive status endpoint always returns idle since CognitiveLoop was removed."""
    resp = api_client.get("/api/cognitive/status")
    assert resp.status_code == 200
    body = resp.json()

    assert body["running"] is False
    # memory_recall may be empty, that's fine
    assert isinstance(body.get("memory_recall", []), list)
