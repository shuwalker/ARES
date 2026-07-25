"""FastAPI and service tests for MCP server management (issue #538)."""

from __future__ import annotations

from copy import deepcopy

from fastapi.testclient import TestClient
import pytest

from api import mcp_config
from fastapi_app.main import create_app


SAMPLE_MCP = {
    "searxng": {"command": "mcp-searxng", "args": ["--port", "8888"], "timeout": 120},
    "web-reader": {
        "url": "http://localhost:3001/mcp",
        "timeout": 60,
        "headers": {"Authorization": "Bearer secret123"},
    },
}


@pytest.fixture()
def mcp_store(monkeypatch):
    state = {"mcp_servers": deepcopy(SAMPLE_MCP)}

    def servers():
        return state, state["mcp_servers"]

    monkeypatch.setattr(mcp_config, "_servers", servers)
    monkeypatch.setattr(mcp_config, "_save", lambda config, values: config.update(mcp_servers=values))
    monkeypatch.setattr(mcp_config, "runtime_status_by_name", lambda: {})
    return state


@pytest.fixture()
def client():
    with TestClient(create_app()) as value:
        yield value


def test_list_route_returns_masked_profile_scoped_catalog(client, mcp_store, monkeypatch):
    monkeypatch.setattr(
        mcp_config,
        "runtime_status_by_name",
        lambda: {"searxng": {"connected": True, "tools": 3}},
    )
    response = client.get("/api/mcp/servers")
    assert response.status_code == 200
    payload = response.json()
    by_name = {row["name"]: row for row in payload["servers"]}
    assert payload["toggle_supported"] is True
    assert by_name["searxng"]["status"] == "active"
    assert by_name["searxng"]["tool_count"] == 3
    assert by_name["web-reader"]["headers"]["Authorization"] == mcp_config.MASKED_PLACEHOLDER


def test_list_route_survives_an_empty_catalog(client, mcp_store):
    mcp_store["mcp_servers"].clear()
    response = client.get("/api/mcp/servers")
    assert response.status_code == 200
    assert response.json()["servers"] == []


@pytest.mark.parametrize(
    ("name", "payload", "field", "value"),
    [
        ("stdio", {"command": "test-cmd", "timeout": 30}, "command", "test-cmd"),
        ("http", {"url": "http://localhost:4000", "timeout": 60}, "url", "http://localhost:4000"),
    ],
)
def test_put_route_adds_server(client, mcp_store, name, payload, field, value):
    response = client.put(f"/api/mcp/servers/{name}", json=payload)
    assert response.status_code == 200
    assert response.json()["server"][field] == value
    assert mcp_store["mcp_servers"][name][field] == value


def test_put_route_preserves_masked_secret(client, mcp_store):
    response = client.put(
        "/api/mcp/servers/web-reader",
        json={
            "url": "http://localhost:3001/mcp",
            "headers": {"Authorization": mcp_config.MASKED_PLACEHOLDER},
        },
    )
    assert response.status_code == 200
    assert mcp_store["mcp_servers"]["web-reader"]["headers"]["Authorization"] == "Bearer secret123"


def test_put_route_rejects_missing_transport(client, mcp_store):
    response = client.put("/api/mcp/servers/broken", json={"timeout": 30})
    assert response.status_code == 400
    assert "url or command" in response.json()["error"]


def test_patch_route_toggles_server(client, mcp_store):
    response = client.patch("/api/mcp/servers/searxng", json={"enabled": False})
    assert response.status_code == 200
    assert mcp_store["mcp_servers"]["searxng"]["enabled"] is False


def test_delete_route_removes_only_selected_server(client, mcp_store):
    response = client.delete("/api/mcp/servers/searxng")
    assert response.status_code == 200
    assert "searxng" not in mcp_store["mcp_servers"]
    assert "web-reader" in mcp_store["mcp_servers"]


@pytest.mark.parametrize("method", ["patch", "delete"])
def test_missing_server_returns_404(client, mcp_store, method):
    kwargs = {"json": {"enabled": False}} if method == "patch" else {}
    response = getattr(client, method)("/api/mcp/servers/missing", **kwargs)
    assert response.status_code == 404


def test_service_helpers_mask_secrets_and_parse_enabled():
    masked = mcp_config.mask_secrets(
        {"headers": {"Authorization": "Bearer token", "Accept": "application/json"}}
    )
    assert masked["headers"]["Authorization"] == mcp_config.MASKED_PLACEHOLDER
    assert masked["headers"]["Accept"] == "application/json"
    assert mcp_config.parse_enabled(0) is False
    assert mcp_config.parse_enabled("off") is False
    assert mcp_config.parse_enabled(None) is True


def test_server_summary_contracts():
    stdio = mcp_config.server_summary("searxng", SAMPLE_MCP["searxng"])
    http = mcp_config.server_summary("web-reader", SAMPLE_MCP["web-reader"])
    invalid = mcp_config.server_summary("broken", "not-a-dict")
    assert stdio["transport"] == "stdio"
    assert stdio["timeout"] == 120
    assert http["transport"] == "http"
    assert http["headers"]["Authorization"] == mcp_config.MASKED_PLACEHOLDER
    assert invalid["status"] == "invalid_config"


def test_strip_masked_values_preserves_existing_secret():
    result = mcp_config.strip_masked_values(
        {"API_KEY": mcp_config.MASKED_PLACEHOLDER, "PUBLIC": "updated"},
        {"API_KEY": "real-secret", "PUBLIC": "old"},
    )
    assert result == {"API_KEY": "real-secret", "PUBLIC": "updated"}
