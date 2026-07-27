"""FastAPI handoff summaries remain useful without a connected model runtime."""

import pytest
from fastapi.testclient import TestClient

import api.handoff_summary as handoff
from fastapi_app.main import create_app
from fastapi_app.request_context import RequestIdentity, require_mutation_identity


IDENTITY = RequestIdentity(session_cookie=None, profile="default", auth_enabled=False)


@pytest.fixture
def client(monkeypatch):
    import api.models as models
    import api.session_access as access

    monkeypatch.setattr(models, "CONVERSATION_ROUND_THRESHOLD", 2)
    monkeypatch.setattr(models, "count_conversation_rounds", lambda session_id, since=None: 3)
    monkeypatch.setattr(
        models,
        "get_cli_session_messages",
        lambda _session_id: [
            {"role": "user", "content": "Please finish the deployment plan", "timestamp": 1.0},
            {"role": "assistant", "content": "I prepared the rollout checklist", "timestamp": 2.0},
        ],
    )
    monkeypatch.setattr(access, "session_is_subagent_view_only", lambda _session_id: False)
    monkeypatch.setattr(handoff, "_persist_local", lambda *_args: True)
    app = create_app()
    app.dependency_overrides[require_mutation_identity] = lambda: IDENTITY
    with TestClient(app) as value:
        yield value


def test_handoff_summary_falls_back_gracefully_without_runtime(client):
    response = client.post("/api/session/handoff-summary", json={"session_id": "session-1"})
    assert response.status_code == 200
    assert response.json() == {
        "ok": True,
        "summary": (
            "- You asked: Please finish the deployment plan.\n"
            "- The assistant responded: I prepared the rollout checklist.\n"
            "- There is pending context to continue next."
        ),
        "message_count": 2,
        "rounds": 3,
        "fallback": True,
    }


def test_handoff_summary_rejects_invalid_since(client):
    response = client.post(
        "/api/session/handoff-summary",
        json={"session_id": "session-1", "since": "yesterday"},
    )
    assert response.status_code == 400
    assert response.json()["error"] == "since must be a unix timestamp (number)"
