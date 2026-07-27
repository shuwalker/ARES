"""Profile-authorization contracts exercised through the FastAPI application."""

from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace

from fastapi.testclient import TestClient

from fastapi_app.main import create_app
from fastapi_app.realtime import RealtimeService
from fastapi_app.request_context import (
    RequestIdentity,
    require_identity,
    require_mutation_identity,
)


class _Session(SimpleNamespace):
    def compact(self, **_kwargs):
        return dict(self.__dict__)


def _session(session_id: str, profile: str = "default") -> _Session:
    return _Session(
        session_id=session_id,
        profile=profile,
        workspace="/workspace",
        model="test-model",
        model_provider=None,
        title="Test",
        messages=[],
        context_messages=[],
        tool_calls=[],
        read_only=False,
        active_stream_id=None,
    )


class _FakeAdapter:
    def __init__(self):
        self.started = []

    async def stream_chat(self, request, *, session, profile):
        self.started.append((request.message, session.session_id, profile))
        return {"ok": True, "stream_id": "fake-stream", "session_id": session.session_id}


class _Registry:
    def __init__(self, adapter):
        self.adapter = adapter

    def for_session(self, _session, *, profile=None):
        return self.adapter


def _client(tmp_path: Path, adapter=None) -> TestClient:
    realtime = RealtimeService(adapter_registry=_Registry(adapter or _FakeAdapter()))
    app = create_app(frontend_root=tmp_path / "missing-dist", realtime_service=realtime)
    identity = RequestIdentity(session_cookie=None, profile="default", auth_enabled=False)
    app.dependency_overrides[require_identity] = lambda: identity
    app.dependency_overrides[require_mutation_identity] = lambda: identity
    return TestClient(app)


def test_session_duplicate_foreign_profile_is_hidden(monkeypatch, tmp_path):
    foreign = _session("foreign-duplicate", "other")
    monkeypatch.setattr("api.models.get_session", lambda *_args, **_kwargs: foreign)
    monkeypatch.setattr(
        "api.session_mutations.duplicate_session",
        lambda *_args, **_kwargs: (_ for _ in ()).throw(AssertionError("duplicate ran")),
    )

    response = _client(tmp_path).post(
        "/api/session/duplicate",
        json={"session_id": foreign.session_id},
    )

    assert response.status_code == 404


def test_file_mutation_foreign_profile_is_hidden_before_file_access(monkeypatch, tmp_path):
    foreign = _session("foreign-file", "other")
    monkeypatch.setattr("api.models.get_session_for_file_ops", lambda _sid: foreign)
    monkeypatch.setattr("api.profiles.get_active_profile_name", lambda: "default")

    response = _client(tmp_path).post(
        "/api/file/save",
        json={"session_id": foreign.session_id, "path": "notes.txt", "content": "x"},
    )

    assert response.status_code == 404


def test_chat_start_foreign_profile_does_not_reach_adapter(monkeypatch, tmp_path):
    foreign = _session("foreign-chat", "other")
    adapter = _FakeAdapter()
    monkeypatch.setattr("api.models.get_session", lambda *_args, **_kwargs: foreign)

    response = _client(tmp_path, adapter).post(
        "/api/chat/start",
        json={"session_id": foreign.session_id, "message": "hello"},
    )

    assert response.status_code == 404
    assert adapter.started == []


def test_chat_start_same_profile_uses_fake_adapter(monkeypatch, tmp_path):
    visible = _session("visible-chat")
    adapter = _FakeAdapter()
    monkeypatch.setattr("api.models.get_session", lambda *_args, **_kwargs: visible)

    response = _client(tmp_path, adapter).post(
        "/api/chat/start",
        json={"session_id": visible.session_id, "message": "hello"},
    )

    assert response.status_code == 200
    assert response.json()["stream_id"] == "fake-stream"
    assert adapter.started == [("hello", visible.session_id, "default")]


def test_stream_owner_unregistered_on_worker_early_return():
    from api import config
    import api.streaming as streaming

    with config.STREAM_SESSION_OWNERS_LOCK:
        previous = dict(config.STREAM_SESSION_OWNERS)
        config.STREAM_SESSION_OWNERS.clear()
    config.register_stream_owner("leak-stream", "some-session")
    try:
        with config.STREAMS_LOCK:
            config.STREAMS.pop("leak-stream", None)
        streaming._run_agent_streaming("some-session", "hi", "m", "/tmp", "leak-stream")
        with config.STREAM_SESSION_OWNERS_LOCK:
            assert "leak-stream" not in config.STREAM_SESSION_OWNERS
    finally:
        with config.STREAM_SESSION_OWNERS_LOCK:
            config.STREAM_SESSION_OWNERS.clear()
            config.STREAM_SESSION_OWNERS.update(previous)
