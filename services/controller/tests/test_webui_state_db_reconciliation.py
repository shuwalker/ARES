"""Canonical state.db/sidecar reconciliation at the FastAPI service boundary."""

from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

from fastapi.testclient import TestClient

from api.models import merge_session_messages_append_only
from api.session_projection import metadata_only_message_summary, project_session_detail
from fastapi_app.dependencies import get_core_service
from fastapi_app.main import create_app


def _message(role, content, timestamp, **extra):
    return {"role": role, "content": content, "timestamp": timestamp, **extra}


class _Session:
    def __init__(self, messages, *, tool_calls=None):
        self.session_id = "session-1"
        self.profile = "default"
        self.messages = list(messages)
        self.tool_calls = list(tool_calls or [])
        self.truncation_watermark = None
        self.truncation_boundary = None
        self.active_stream_id = None
        self.pending_user_message = None
        self.pending_attachments = []
        self.pending_started_at = None
        self.model = "test-model"
        self.model_provider = "test-provider"

    def compact(self, **_kwargs):
        return {
            "session_id": self.session_id,
            "profile": self.profile,
            "model": self.model,
            "model_provider": self.model_provider,
        }


def _projection_dependencies(monkeypatch, state_rows):
    import api.model_context
    import api.model_resolution
    import api.models
    import api.session_projection as projection

    monkeypatch.setattr(
        projection,
        "webui_sidecar_lineage_messages_for_display",
        lambda session: list(session.messages),
    )
    monkeypatch.setattr(
        projection,
        "merged_webui_lineage_messages_for_display",
        lambda _session, messages: list(messages),
    )
    monkeypatch.setattr(api.models, "get_state_db_session_messages", lambda *_a, **_k: list(state_rows))
    monkeypatch.setattr(api.model_context, "session_context_projection", lambda *_a, **_k: (4096, 3072))
    monkeypatch.setattr(
        api.model_resolution,
        "_resolve_effective_session_model_for_display",
        lambda session: session.model,
    )
    monkeypatch.setattr(
        api.model_resolution,
        "_resolve_effective_session_model_provider_for_display",
        lambda session: session.model_provider,
    )


def test_state_database_suffix_extends_sidecar_without_duplicate_prefix(monkeypatch):
    sidecar = [
        _message("user", "hello", 1),
        _message("assistant", "hi", 2),
    ]
    state = sidecar + [_message("user", "new turn", 3)]
    _projection_dependencies(monkeypatch, state)

    payload = project_session_detail(_Session(sidecar))
    assert payload["messages"] == state
    assert payload["message_count"] == 3
    assert payload["last_message_at"] == 3


def test_sidecar_only_rows_and_distinct_same_content_rows_are_preserved(monkeypatch):
    sidecar = [
        _message("user", "repeat", 1, message_id="sidecar-only"),
        _message("user", "repeat", 2, message_id="second"),
    ]
    _projection_dependencies(monkeypatch, [_message("assistant", "state", 3)])
    payload = project_session_detail(_Session(sidecar))
    assert [row["content"] for row in payload["messages"]] == ["repeat", "repeat", "state"]
    assert payload["messages"][0]["message_id"] == "sidecar-only"


def test_paginated_projection_rebases_tool_call_indexes_and_bounds_tool_output(monkeypatch):
    rows = [
        _message("user", "one", 1),
        _message("assistant", "two", 2),
        _message("tool", "x" * 5000, 3, tool_call_id="call-1", tool_name="read"),
        _message("assistant", "four", 4),
    ]
    _projection_dependencies(monkeypatch, rows)
    session = _Session(
        rows,
        tool_calls=[{"assistant_msg_idx": 3, "name": "read", "id": "call-1"}],
    )
    payload = project_session_detail(session, message_limit=2)
    # Render windows are counted by conversational rows, so the assistant row
    # paired with the tool result is retained around the two-row limit.
    assert payload["messages_start"] == 1
    assert payload["messages_has_more"] is True
    assert payload["messages"][1]["tool_call_id"] == "call-1"
    assert payload["messages"][1]["_content_truncated"] is True
    assert payload["tool_calls"][0]["assistant_msg_idx"] == 2


def test_metadata_poll_uses_newer_state_database_summary_without_loading_rows(monkeypatch):
    import api.models

    sidecar = SimpleNamespace(
        _metadata_message_count=2,
        updated_at=10,
        truncation_watermark=None,
        compact=lambda: {"message_count": 2},
    )
    monkeypatch.setattr(api.models.Session, "load_metadata_only", staticmethod(lambda _sid: sidecar))
    monkeypatch.setattr(
        api.models,
        "get_state_db_session_summary",
        lambda *_a, **_k: {"message_count": 4, "last_message_at": 20},
    )
    monkeypatch.setattr(
        api.models,
        "get_state_db_session_messages",
        lambda *_a, **_k: (_ for _ in ()).throw(AssertionError("full read not allowed")),
    )
    assert metadata_only_message_summary("session-1", profile="default") == {
        "message_count": 4,
        "last_message_at": 20.0,
    }


def test_fastapi_session_route_preserves_projection_contract(tmp_path, monkeypatch):
    import api.auth

    monkeypatch.setattr(api.auth, "is_auth_enabled", lambda: False)
    dist = tmp_path / "dist"
    dist.mkdir()
    (dist / "index.html").write_text("<div id='root'></div>", encoding="utf-8")

    class Service:
        def session(self, session_id, *, profile, load_messages, message_limit):
            assert (session_id, load_messages, message_limit) == ("session-1", True, 2)
            return {
                "session": {
                    "session_id": session_id,
                    "messages": [_message("assistant", "ready", 1)],
                    "message_count": 1,
                    "messages_total": 1,
                    "messages_start": 0,
                    "messages_has_more": False,
                }
            }

    app = create_app(frontend_root=dist)
    app.dependency_overrides[get_core_service] = Service
    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        response = client.get("/api/session?session_id=session-1&messages=true&msg_limit=2")
    assert response.status_code == 200
    assert response.json()["session"]["messages"][0]["content"] == "ready"
