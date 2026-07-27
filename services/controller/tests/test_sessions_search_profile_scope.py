from types import SimpleNamespace

from fastapi.testclient import TestClient

from fastapi_app.main import create_app


def _run_search(monkeypatch, query):
    sessions_meta = [
        {"session_id": "active-s", "title": "boring", "profile": "default"},
        {"session_id": "other-s", "title": "secret needle title", "profile": "other"},
        {"session_id": "other-content-s", "title": "boring", "profile": "other"},
    ]
    sessions = {
        "other-content-s": SimpleNamespace(messages=[{"role": "user", "content": "secret needle body"}]),
        "active-s": SimpleNamespace(messages=[{"role": "user", "content": "nothing"}]),
        "other-s": SimpleNamespace(messages=[]),
    }
    monkeypatch.setattr("api.auth.is_auth_enabled", lambda: False)
    monkeypatch.setattr("api.models.all_sessions", lambda: list(sessions_meta))
    monkeypatch.setattr("api.models.get_session", lambda sid: sessions[sid])
    monkeypatch.setattr("api.profiles.get_active_profile_name", lambda: "default")
    with TestClient(create_app()) as client:
        response = client.get(query)
    assert response.status_code == 200
    return response.json()


def test_empty_session_search_scopes_to_active_profile(monkeypatch):
    result = _run_search(monkeypatch, "/api/sessions/search")
    assert [row["session_id"] for row in result["sessions"]] == ["active-s"]


def test_title_search_should_not_return_other_profile_rows(monkeypatch):
    result = _run_search(monkeypatch, "/api/sessions/search?q=needle&content=0")
    assert result["count"] == 0


def test_content_search_should_not_return_other_profile_rows(monkeypatch):
    result = _run_search(monkeypatch, "/api/sessions/search?q=needle&content=1&depth=0")
    assert result["count"] == 0


def test_all_profiles_opt_in_keeps_aggregate_session_search(monkeypatch):
    result = _run_search(monkeypatch, "/api/sessions/search?all_profiles=1")
    assert result["all_profiles"] is True
    assert [row["session_id"] for row in result["sessions"]] == [
        "active-s",
        "other-s",
        "other-content-s",
    ]
