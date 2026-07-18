"""Durable run replay contracts used by FastAPI transports."""

from __future__ import annotations

from types import SimpleNamespace

from api.run_journal import append_run_event
from fastapi_app.adapters.frameworks import AresAdapter


def _adapter(monkeypatch):
    adapter = AresAdapter()
    monkeypatch.setattr(adapter, "check_health", lambda **_kwargs: SimpleNamespace(available=True))
    return adapter


def test_adapter_status_exposes_durable_replay_summary(tmp_path, monkeypatch):
    import api.models

    monkeypatch.setattr(api.models, "SESSION_DIR", tmp_path)
    append_run_event("session-1", "run-1", "token", {"text": "hello"}, session_dir=tmp_path)
    append_run_event("session-1", "run-1", "stream_end", {"status": "completed"}, session_dir=tmp_path)

    status = _adapter(monkeypatch).stream_status("run-1")
    assert status["active"] is False
    assert status["replay_available"] is True
    assert status["journal"]["terminal"] is True
    assert status["journal"]["last_event_id"] == "run-1:2"


def test_adapter_replays_only_events_after_opaque_cursor(tmp_path, monkeypatch):
    import api.models

    monkeypatch.setattr(api.models, "SESSION_DIR", tmp_path)
    for text in ("one", "two", "three"):
        append_run_event("session-1", "run-1", "token", {"text": text}, session_dir=tmp_path)

    replay = _adapter(monkeypatch).replay_stream("run-1", after_event_id="run-1:1")
    assert [event["event_id"] for event in replay] == ["run-1:2", "run-1:3"]
    assert [event["payload"]["text"] for event in replay] == ["two", "three"]


def test_foreign_run_cursor_does_not_truncate_current_run(tmp_path, monkeypatch):
    import api.models

    monkeypatch.setattr(api.models, "SESSION_DIR", tmp_path)
    append_run_event("session-1", "run-new", "token", {"text": "fresh"}, session_dir=tmp_path)
    replay = _adapter(monkeypatch).replay_stream("run-new", after_event_id="run-old:99")
    assert [event["event_id"] for event in replay] == ["run-new:1"]


def test_missing_journal_is_a_graceful_empty_replay(tmp_path, monkeypatch):
    import api.models

    monkeypatch.setattr(api.models, "SESSION_DIR", tmp_path)
    adapter = _adapter(monkeypatch)
    assert adapter.replay_stream("missing-run") == []
    assert adapter.stream_status("missing-run")["replay_available"] is False
