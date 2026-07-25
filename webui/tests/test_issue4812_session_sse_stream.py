"""Per-session durable replay contracts for the FastAPI activity stream."""

from __future__ import annotations

import asyncio
import queue
from pathlib import Path

from fastapi.testclient import TestClient

from api.run_journal import append_run_event, read_session_run_events
from fastapi_app.main import create_app
from fastapi_app.realtime import QueueSubscription
from fastapi_app.request_context import RequestIdentity
from fastapi_app.routers.realtime import _session_activity_sse_response


class _Channel:
    def unsubscribe(self, _subscriber):
        return None


class _Service:
    def __init__(self, *, deny=False):
        self.deny = deny

    def session_activity_subscription(self, session_id, *, profile):
        if self.deny:
            from fastapi_app.errors import CoreApiError

            raise CoreApiError(404, "Session not found")
        return QueueSubscription(_Channel(), queue.Queue(), {}, session_id)

    def session_snapshot(self, session_id, *, profile):
        return {"session_id": session_id, "profile": profile, "active": False}


def test_session_journal_replays_suffix_and_later_runs(tmp_path):
    append_run_event("session-1", "run-a", "token", {"text": "a1"}, session_dir=tmp_path)
    append_run_event("session-1", "run-a", "stream_end", {}, session_dir=tmp_path)
    append_run_event("session-1", "run-b", "token", {"text": "b1"}, session_dir=tmp_path)

    replay = read_session_run_events(
        "session-1",
        after_event_id="run-a:1",
        session_dir=tmp_path,
    )
    assert replay["status"] == "ok"
    assert [event["event_id"] for event in replay["events"]] == ["run-a:2", "run-b:1"]


def test_session_journal_rejects_foreign_and_hostile_cursors(tmp_path):
    append_run_event("session-2", "foreign", "token", {}, session_dir=tmp_path)
    foreign = read_session_run_events(
        "session-1",
        after_event_id="foreign:1",
        session_dir=tmp_path,
    )
    hostile = read_session_run_events(
        "session-1",
        after_event_id="../../foreign:1",
        session_dir=tmp_path,
    )
    assert foreign["status"] == "cursor_session_mismatch"
    assert foreign["events"] == []
    assert hostile["status"] == "cursor_invalid"
    assert hostile["events"] == []


def test_session_journal_rejects_noncontiguous_rows(tmp_path):
    append_run_event("session-1", "run-a", "token", {}, session_dir=tmp_path, seq=1)
    append_run_event("session-1", "run-a", "token", {}, session_dir=tmp_path, seq=3)
    replay = read_session_run_events(
        "session-1",
        after_event_id="run-a:1",
        session_dir=tmp_path,
    )
    assert replay["status"] == "replay_noncontiguous"
    assert replay["events"] == []


def test_session_sse_emits_durable_event_ids_before_live_wait(tmp_path, monkeypatch):
    import api.models

    monkeypatch.setattr(api.models, "SESSION_DIR", tmp_path)
    append_run_event("session-1", "run-a", "token", {"text": "one"}, session_dir=tmp_path, seq=1)
    append_run_event("session-1", "run-a", "token", {"text": "two"}, session_dir=tmp_path, seq=2)

    response = asyncio.run(
        _session_activity_sse_response(
            _Service(),
            "session-1",
            "default",
            after_event_id="run-a:1",
        )
    )

    async def first_two():
        iterator = response.body_iterator
        return await iterator.__anext__(), await iterator.__anext__()

    initial, replayed = asyncio.run(first_two())
    assert b"event: initial" in initial
    assert b"id: run-a:2" in replayed
    assert b'"text":"two"' in replayed


def test_hidden_session_is_rejected_before_stream_headers(tmp_path, monkeypatch):
    import api.auth

    monkeypatch.setattr(api.auth, "is_auth_enabled", lambda: False)
    dist = tmp_path / "dist"
    dist.mkdir()
    (dist / "index.html").write_text("<div id='root'></div>", encoding="utf-8")
    app = create_app(frontend_root=dist, realtime_service=_Service(deny=True))
    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        response = client.get("/api/sessions/hidden/events")
    assert response.status_code == 404
