import pytest


@pytest.fixture
def api_client(monkeypatch):
    pytest.importorskip("fastapi")
    pytest.importorskip("fastapi.testclient")

    monkeypatch.setattr("ares.api.SERVICES", [])

    from ares.api import create_app
    from fastapi.testclient import TestClient

    app = create_app()
    with TestClient(app) as client:
        yield client


def test_stack_endpoint_exposes_rebuild_manifest(api_client):
    resp = api_client.get("/api/stack")
    assert resp.status_code == 200
    body = resp.json()
    assert body["name"] == "ARES 2"
    assert body["current_milestone"] == "avatar_companion_foundation"
    assert [layer["name"] for layer in body["layers"]] == [
        "presence",
        "runtime",
        "memory",
        "perception",
        "reasoning",
        "tools",
        "approval",
        "workflows",
    ]
