"""FastAPI activity-scene persistence is bounded and message-scoped."""

import contextlib

import pytest
from fastapi.testclient import TestClient

from fastapi_app.main import create_app
from fastapi_app.request_context import RequestIdentity, require_mutation_identity


IDENTITY = RequestIdentity(session_cookie=None, profile="default", auth_enabled=False)


class FakeSession:
    def __init__(self):
        self.profile = "default"
        self.messages = [
            {"role": "user", "content": "question"},
            {"role": "assistant", "content": "answer", "_turnDuration": 1.25},
        ]
        self.anchor_activity_scenes = {}
        self.saved = []

    def save(self, **kwargs):
        self.saved.append(kwargs)


@pytest.fixture
def scene_client(monkeypatch):
    session = FakeSession()
    import api.config as config
    import api.session_access as access

    monkeypatch.setattr(access, "get_or_materialize_session", lambda _session_id: session)
    monkeypatch.setattr(config, "_get_session_agent_lock", lambda _session_id: contextlib.nullcontext())
    app = create_app()
    app.dependency_overrides[require_mutation_identity] = lambda: IDENTITY
    with TestClient(app) as client:
        yield client, session


def _scene(rows=None):
    return {
        "version": "activity_scene_v1",
        "activity_rows": rows if rows is not None else [{"kind": "prose", "text": "answer"}],
        "final_answer": "answer",
    }


def test_anchor_scene_persists_against_assistant_message(scene_client):
    client, session = scene_client
    response = client.post(
        "/api/session/anchor-scene",
        json={"session_id": "session-1", "message_index": 1, "scene": _scene()},
    )
    assert response.status_code == 200
    assert response.json()["message_index"] == 1
    record = next(iter(session.anchor_activity_scenes.values()))
    assert record["scene"]["turn_duration"] == 1.25
    assert session.saved == [{"touch_updated_at": False, "skip_index": True}]


def test_anchor_scene_rejects_non_assistant_index(scene_client):
    client, _session = scene_client
    response = client.post(
        "/api/session/anchor-scene",
        json={"session_id": "session-1", "message_index": 0, "message_ref": "missing", "scene": _scene()},
    )
    assert response.status_code == 404
    assert response.json()["error"] == "Assistant message not found"


def test_anchor_scene_rejects_unbounded_row_count(scene_client):
    client, _session = scene_client
    response = client.post(
        "/api/session/anchor-scene",
        json={"session_id": "session-1", "scene": _scene([{}] * 1001)},
    )
    assert response.status_code == 400
    assert response.json()["error"] == "scene.activity_rows is too large"
