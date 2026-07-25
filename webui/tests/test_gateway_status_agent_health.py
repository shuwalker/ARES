"""FastAPI contract coverage for the messaging gateway status projection."""

from pathlib import Path

from fastapi.testclient import TestClient

from fastapi_app.main import create_app


def _call_gateway_status(monkeypatch, agent_health_alive, identity_map=None, details=None):
    from api import gateway_status

    monkeypatch.setattr("api.auth.is_auth_enabled", lambda: False)
    monkeypatch.setattr(
        gateway_status,
        "build_agent_health_payload",
        lambda: {
            "alive": agent_health_alive,
            "checked_at": "2026-05-06T12:00:00+00:00",
            "details": details or {},
        },
    )
    monkeypatch.setattr(
        gateway_status,
        "load_gateway_session_identity_map",
        lambda: identity_map or {},
    )
    monkeypatch.setattr(
        gateway_status,
        "gateway_session_metadata_path",
        lambda: Path("/definitely-not-an-ares-session-file"),
    )
    with TestClient(create_app()) as client:
        response = client.get("/api/gateway/status")
    assert response.status_code == 200
    return response.json()


def test_gateway_status_running_true_when_agent_health_alive_and_no_sessions(monkeypatch):
    result = _call_gateway_status(monkeypatch, True, {})
    assert result["running"] is True
    assert result["configured"] is True
    assert result["platforms"] == []


def test_gateway_status_running_false_when_agent_health_alive_false_and_no_sessions(monkeypatch):
    result = _call_gateway_status(monkeypatch, False, {})
    assert result["running"] is False
    assert result["configured"] is True
    assert result["platforms"] == []


def test_gateway_status_running_false_when_agent_health_alive_none_and_no_sessions(monkeypatch):
    result = _call_gateway_status(monkeypatch, None, {})
    assert result["running"] is False
    assert result["configured"] is False


def test_gateway_status_projects_connected_platforms(monkeypatch):
    identity_map = {
        "a": {"raw_source": "telegram", "platform": "telegram"},
        "b": {"raw_source": "discord", "platform": "discord"},
    }
    result = _call_gateway_status(monkeypatch, True, identity_map)
    assert result["running"] is True
    assert {item["name"] for item in result["platforms"]} == {"telegram", "discord"}


def test_alive_none_falls_back_to_existing_gateway_sessions(monkeypatch):
    result = _call_gateway_status(
        monkeypatch,
        None,
        {"a": {"raw_source": "telegram", "platform": "telegram"}},
    )
    assert result["running"] is True
    assert result["configured"] is True


def test_corrupt_or_missing_session_metadata_is_an_empty_projection(monkeypatch):
    result = _call_gateway_status(monkeypatch, True, {})
    assert result["session_count"] == 0
    assert result["platforms"] == []


def test_blank_platform_fields_are_ignored(monkeypatch):
    result = _call_gateway_status(
        monkeypatch,
        True,
        {"a": {"raw_source": "", "platform": ""}, "b": {}},
    )
    assert result["running"] is True
    assert result["platforms"] == []


def test_explicit_down_health_is_authoritative_over_existing_sessions(monkeypatch):
    result = _call_gateway_status(
        monkeypatch,
        False,
        {"a": {"raw_source": "telegram", "platform": "telegram"}},
    )
    assert result["running"] is False
    assert result["configured"] is True
    assert result["platforms"][0]["name"] == "telegram"


def test_gateway_health_metadata_is_preserved(monkeypatch):
    result = _call_gateway_status(
        monkeypatch,
        None,
        {},
        details={
            "state": "unknown",
            "reason": "gateway_stale_running_state",
            "gateway_state": "running",
        },
    )
    assert result["configured"] is True
    assert result["health"] == {
        "state": "unknown",
        "reason": "gateway_stale_running_state",
        "gateway_state": "running",
    }


def test_last_active_is_empty_without_a_sessions_file(monkeypatch):
    result = _call_gateway_status(monkeypatch, True, {})
    assert result["last_active"] == ""
