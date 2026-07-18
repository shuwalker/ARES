import api.models as models
import api.profiles as profiles
import api.session_runtime_state as runtime_state


def test_sessions_list_reconciles_stale_stream_state_before_serializing(monkeypatch):
    from fastapi.testclient import TestClient
    from fastapi_app.main import create_app
    from fastapi_app.request_context import RequestIdentity, require_identity

    repaired = {"value": False}
    all_sessions_calls = {"count": 0}

    class _Session:
        def __init__(self):
            self.session_id = "stale-session"
            self.active_stream_id = "stale-stream"

    def fake_all_sessions(diag=None, **_kwargs):
        all_sessions_calls["count"] += 1
        if repaired["value"]:
            active_stream_id = None
            is_streaming = False
        else:
            active_stream_id = "stale-stream"
            is_streaming = False
        return [
            {
                "session_id": "stale-session",
                "title": "Stale Session",
                "profile": "default",
                "message_count": 1,
                "active_stream_id": active_stream_id,
                "is_streaming": is_streaming,
                "updated_at": 1,
                "last_message_at": 1,
            }
        ]

    def fake_get_session(session_id, metadata_only=False):
        assert session_id == "stale-session"
        assert metadata_only is True
        return _Session()

    def fake_clear_stale_stream_state(session):
        repaired["value"] = True
        session.active_stream_id = None
        return True

    monkeypatch.setattr(models, "all_sessions", fake_all_sessions)
    monkeypatch.setattr(models, "get_session", fake_get_session)
    monkeypatch.setattr(runtime_state, "clear_stale_stream_state", fake_clear_stale_stream_state)
    monkeypatch.setattr("api.config.load_settings", lambda: {"show_cli_sessions": False})
    monkeypatch.setattr(profiles, "get_active_profile_name", lambda: "default")

    app = create_app()
    app.dependency_overrides[require_identity] = lambda: RequestIdentity(None, "default", False)
    with TestClient(app) as client:
        response = client.get("/api/sessions")

    assert response.status_code == 200
    payload = response.json()
    sessions = payload["sessions"]
    assert all_sessions_calls["count"] == 2
    assert repaired["value"] is True
    assert sessions[0]["active_stream_id"] is None
    assert sessions[0]["is_streaming"] is False


def test_reconcile_stale_stream_state_skips_live_stream_rows(monkeypatch):
    loaded = []

    def fake_get_session(session_id, metadata_only=False):
        loaded.append((session_id, metadata_only))
        raise AssertionError("live stream rows should not be loaded for cleanup")

    monkeypatch.setattr(models, "get_session", fake_get_session)

    changed = runtime_state.reconcile_stale_stream_state_for_session_rows([
        {
            "session_id": "live-session",
            "active_stream_id": "live-stream",
            "is_streaming": True,
        }
    ])

    assert changed is False
    assert loaded == []
