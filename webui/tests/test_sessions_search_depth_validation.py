from types import SimpleNamespace

from fastapi.testclient import TestClient

from fastapi_app.main import create_app


def _run_search(monkeypatch, query):
    session = SimpleNamespace(
        messages=[
            {"role": "user", "content": "first message"},
            {"role": "assistant", "content": "second message"},
            {"role": "user", "content": "NEEDLE in the latest message"},
        ]
    )
    monkeypatch.setattr("api.auth.is_auth_enabled", lambda: False)
    monkeypatch.setattr(
        "api.models.all_sessions",
        lambda: [{"session_id": "s1", "title": "Untitled", "profile": "default"}],
    )
    monkeypatch.setattr("api.models.get_session", lambda _sid: session)
    monkeypatch.setattr("api.profiles.get_active_profile_name", lambda: "default")
    with TestClient(create_app()) as client:
        response = client.get(query)
    assert response.status_code == 200
    return response.json()


def test_search_non_numeric_depth_does_not_500(monkeypatch):
    assert _run_search(monkeypatch, "/api/sessions/search?q=needle&content=1&depth=deep")["count"] == 1


def test_search_negative_depth_still_scans_newest_message(monkeypatch):
    assert _run_search(monkeypatch, "/api/sessions/search?q=needle&content=1&depth=-2")["count"] == 1


def test_search_valid_depth_still_caps_scan(monkeypatch):
    assert _run_search(monkeypatch, "/api/sessions/search?q=needle&content=1&depth=1")["count"] == 0
