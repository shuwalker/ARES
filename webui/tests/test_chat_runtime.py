"""Native chat-run creation contracts for the FastAPI cutover."""

from __future__ import annotations

import inspect
import threading
from types import SimpleNamespace

from api import chat_runtime


class _Session(SimpleNamespace):
    def save(self, **_kwargs):
        self.saved = getattr(self, "saved", 0) + 1


class _Backend:
    def __init__(self, worker):
        self.worker = worker

    def get_worker_target(self):
        return self.worker, False, False


def _session():
    return _Session(
        session_id="session-1",
        title="Untitled",
        workspace="/workspace",
        model="model-1",
        model_provider="provider-1",
        profile="default",
        messages=[],
        active_stream_id=None,
        pending_user_message=None,
        pending_attachments=[],
        pending_started_at=None,
        pending_user_source=None,
        truncation_watermark=None,
    )


def _isolate_runtime(monkeypatch, session):
    monkeypatch.setattr(chat_runtime, "STREAMS", {})
    monkeypatch.setattr(chat_runtime, "STREAMS_LOCK", threading.Lock())
    monkeypatch.setattr(chat_runtime, "ACTIVE_RUNS", {})
    monkeypatch.setattr(chat_runtime, "ACTIVE_RUNS_LOCK", threading.Lock())
    monkeypatch.setattr(chat_runtime, "PENDING_GOAL_CONTINUATION", set())
    monkeypatch.setattr(chat_runtime, "PENDING_BG_TASK_COMPLETIONS", set())
    monkeypatch.setattr(chat_runtime, "STREAM_GOAL_RELATED", {})
    monkeypatch.setattr(chat_runtime, "get_session", lambda *_args, **_kwargs: session)
    monkeypatch.setattr(chat_runtime, "get_config", lambda: {"model": {"default": "model-1"}})
    monkeypatch.setattr(chat_runtime, "get_effective_default_model", lambda _cfg: "model-1")
    monkeypatch.setattr(chat_runtime, "get_last_workspace", lambda: "/workspace")
    monkeypatch.setattr(chat_runtime, "resolve_trusted_workspace", lambda value: value)
    monkeypatch.setattr(chat_runtime, "set_last_workspace", lambda _value: None)
    monkeypatch.setattr(chat_runtime, "get_webui_session_save_mode", lambda: "deferred")
    monkeypatch.setattr(chat_runtime, "_get_session_agent_lock", lambda _sid: threading.Lock())
    monkeypatch.setattr(chat_runtime, "create_stream_channel", lambda: SimpleNamespace())
    monkeypatch.setattr(chat_runtime, "register_stream_owner", lambda *_args: None)
    monkeypatch.setattr(chat_runtime, "unregister_stream_owner", lambda *_args: None)
    monkeypatch.setattr(chat_runtime, "publish_session_list_changed", lambda *_args, **_kwargs: None)


def test_native_chat_runtime_has_no_legacy_route_dependency():
    assert "api.routes" not in inspect.getsource(chat_runtime)


def test_native_chat_runtime_registers_stream_and_starts_worker(monkeypatch):
    session = _session()
    _isolate_runtime(monkeypatch, session)
    worker_calls = []
    thread_calls = []

    def worker(*args, **kwargs):
        worker_calls.append((args, kwargs))

    class ImmediateThread:
        def __init__(self, *, target, args, kwargs, **_rest):
            thread_calls.append((target, args, kwargs))

        def start(self):
            target, args, kwargs = thread_calls[-1]
            target(*args, **kwargs)

    monkeypatch.setattr(chat_runtime.threading, "Thread", ImmediateThread)

    result = chat_runtime.start_session_turn(
        session.session_id,
        "  Hello  ",
        source="webui",
        backend=_Backend(worker),
    )

    assert result["session_id"] == session.session_id
    assert result["stream_id"] in chat_runtime.STREAMS
    assert session.pending_user_message == "Hello"
    assert session.active_stream_id == result["stream_id"]
    assert session.saved == 1
    assert worker_calls[0][0][0] == session.session_id
    assert worker_calls[0][0][1] == "Hello"
    assert worker_calls[0][1]["model_provider"] == "provider-1"


def test_native_chat_runtime_rejects_duplicate_active_stream(monkeypatch):
    session = _session()
    session.active_stream_id = "existing-run"
    _isolate_runtime(monkeypatch, session)
    chat_runtime.STREAMS["existing-run"] = SimpleNamespace()

    result = chat_runtime.start_session_turn(
        session.session_id,
        "Hello",
        source="webui",
        backend=_Backend(lambda *_args, **_kwargs: None),
    )

    assert result == {
        "error": "session already has an active stream",
        "active_stream_id": "existing-run",
        "_status": 409,
    }
