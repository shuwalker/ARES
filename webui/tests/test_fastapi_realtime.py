"""Step 3 WebSocket transport and HTTP control contract tests."""

from __future__ import annotations

import asyncio
import queue
from pathlib import Path
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from fastapi_app.main import create_app
from fastapi_app.realtime import QueueSubscription, RealtimeService
from fastapi_app.routers.realtime import _queue_get
from fastapi_app.request_context import (
    RequestIdentity,
    require_identity,
    require_mutation_identity,
    require_terminal_identity,
)


IDENTITY = RequestIdentity(session_cookie=None, profile="default", auth_enabled=False)


class Channel:
    def __init__(self):
        self.unsubscribed = False

    def unsubscribe(self, _subscriber):
        self.unsubscribed = True


class FakeRealtimeService:
    def __init__(self):
        self.chat_channel = Channel()
        self.activity_channel = Channel()
        self.chat_events: queue.Queue = queue.Queue()
        self.activity_events: queue.Queue = queue.Queue()
        self.chat_events.put(("token", {"text": "Hello"}, "stream-1:1"))
        self.chat_events.put(("tool", {"name": "workspace.read"}, "stream-1:2"))
        self.chat_events.put(("stream_end", {"status": "completed"}, "stream-1:3"))
        self.activity_events.put(("server_turn_started", {"stream_id": "stream-2"}))
        self.terminal = SimpleNamespace(
            output=queue.Queue(),
            closed=SimpleNamespace(is_set=lambda: False),
            proc=SimpleNamespace(poll=lambda: None),
        )
        self.terminal.output.put(("output", {"text": "$ ready\n"}))
        self.terminal.output.put(("terminal_closed", {"exit_code": 0}))

    async def start_chat(self, request, *, profile):
        assert profile == "default"
        return {"stream_id": "stream-1", "session_id": request.session_id, "title": "Today"}

    def stream_status(self, stream_id, *, profile):
        return {"active": True, "stream_id": stream_id, "replay_available": True}

    def cancel_chat(self, stream_id, *, profile):
        return {"ok": True, "cancelled": True, "stream_id": stream_id}

    def authorize_stream(self, stream_id, *, profile):
        assert stream_id == "stream-1"
        assert profile in {None, "default"}
        return "session-1"

    def chat_subscription(self, stream_id, *, profile):
        self.authorize_stream(stream_id, profile=profile)
        return QueueSubscription(self.chat_channel, self.chat_events, {}, "session-1")

    def replay_chat(self, stream_id, *, profile=None, after_event_id=None):
        assert stream_id == "stream-1"
        assert profile in {None, "default"}
        assert after_event_id in {None, "stream-1:0"}
        return []

    def session_activity_subscription(self, session_id, *, profile):
        assert (session_id, profile) == ("session-1", None)
        return QueueSubscription(self.activity_channel, self.activity_events, {}, session_id)

    def start_terminal(self, request, *, profile):
        return {"ok": True, "session_id": request.session_id, "workspace": "/tmp", "running": True}

    def terminal_input(self, request, *, profile):
        return {"ok": True}

    def close_terminal(self, request, *, profile):
        return {"ok": True, "closed": True}

    def terminal_queue(self, session_id, *, profile):
        assert (session_id, profile) == ("session-1", None)
        return self.terminal


@pytest.fixture
def realtime_service():
    return FakeRealtimeService()


@pytest.fixture(autouse=True)
def disable_auth_for_transport_contract(monkeypatch):
    import api.auth

    monkeypatch.setattr(api.auth, "is_auth_enabled", lambda: False)


@pytest.fixture
def app(tmp_path: Path, realtime_service):
    frontend = tmp_path / "dist"
    frontend.mkdir()
    (frontend / "index.html").write_text("<div id='root'></div>", encoding="utf-8")
    application = create_app(frontend_root=frontend, realtime_service=realtime_service)
    application.dependency_overrides[require_identity] = lambda: IDENTITY
    application.dependency_overrides[require_mutation_identity] = lambda: IDENTITY
    application.dependency_overrides[require_terminal_identity] = lambda: IDENTITY
    return application


def websocket(client: TestClient, path: str):
    return client.websocket_connect(
        path,
        subprotocols=["ares-v1"],
        headers={"origin": "http://testserver"},
    )


def test_chat_http_controls_preserve_react_contract(app):
    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        started = client.post("/api/chat/start", json={"session_id": "session-1", "message": "Hello"})
        status = client.get("/api/chat/stream/status?stream_id=stream-1")
        cancelled = client.post("/api/chat/cancel?stream_id=stream-1")

    assert started.status_code == 200
    assert started.json()["stream_id"] == "stream-1"
    assert status.json()["replay_available"] is True
    assert cancelled.json() == {"ok": True, "cancelled": True, "stream_id": "stream-1"}


def test_chat_websocket_streams_ordered_envelopes_and_unsubscribes(app, realtime_service):
    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        with websocket(client, "/api/chat/stream?stream_id=stream-1&after_event_id=stream-1%3A0") as stream:
            token = stream.receive_json()
            tool = stream.receive_json()
            terminal = stream.receive_json()

    assert token == {
        "schema_version": 1,
        "event": "token",
        "data": {"text": "Hello"},
        "event_id": "stream-1:1",
        "seq": 1,
        "stream_id": "stream-1",
        "session_id": "session-1",
        "terminal": False,
    }
    assert tool["event"] == "tool"
    assert terminal["event"] == "stream_end"
    assert terminal["terminal"] is True
    assert realtime_service.chat_channel.unsubscribed is True


def test_chat_sse_compatibility_stream_preserves_event_ids(app, realtime_service):
    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        response = client.get("/api/chat/stream?stream_id=stream-1")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/event-stream")
    assert "id: stream-1:1\nevent: token" in response.text
    assert 'data: {"text":"Hello"}' in response.text
    assert "id: stream-1:3\nevent: stream_end" in response.text
    assert realtime_service.chat_channel.unsubscribed is True


def test_chat_websocket_closes_after_durable_terminal_replay(app, realtime_service):
    realtime_service.replay_chat = lambda *_args, **_kwargs: [
        {
            "event": "stream_end",
            "event_id": "stream-1:9",
            "payload": {"status": "completed"},
        }
    ]

    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        with websocket(client, "/api/chat/stream?stream_id=stream-1") as stream:
            terminal = stream.receive_json()
            with pytest.raises(WebSocketDisconnect) as exc:
                stream.receive_json()

    assert terminal["event"] == "stream_end"
    assert terminal["event_id"] == "stream-1:9"
    assert exc.value.code == 1000
    assert realtime_service.chat_channel.unsubscribed is True


def test_session_activity_websocket_carries_server_started_turn(app, realtime_service):
    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        with websocket(client, "/api/sessions/session-1/stream") as stream:
            event = stream.receive_json()

    assert event["event"] == "server_turn_started"
    assert event["data"]["stream_id"] == "stream-2"
    assert realtime_service.activity_channel.unsubscribed is True


def test_terminal_websocket_replaces_output_sse(app):
    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        started = client.post(
            "/api/terminal/start",
            json={"session_id": "session-1", "rows": 24, "cols": 80},
        )
        with websocket(client, "/api/terminal/stream?session_id=session-1") as stream:
            output = stream.receive_json()
            closed = stream.receive_json()

    assert started.status_code == 200
    assert output["event"] == "output"
    assert output["data"]["text"] == "$ ready\n"
    assert closed["event"] == "terminal_closed"


def test_websocket_rejects_cross_origin_handshake(app):
    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        with pytest.raises(WebSocketDisconnect) as exc:
            with client.websocket_connect(
                "/api/chat/stream?stream_id=stream-1",
                subprotocols=["ares-v1"],
                headers={"origin": "https://attacker.invalid"},
            ):
                pass

    assert exc.value.code == 4403


def test_authenticated_websocket_requires_session_bound_csrf_subprotocol(
    app,
    monkeypatch,
):
    import api.auth as auth

    monkeypatch.setattr(auth, "is_auth_enabled", lambda: True)
    monkeypatch.setattr(auth, "verify_session", lambda cookie: cookie == "valid-session")
    monkeypatch.setattr(
        auth,
        "verify_csrf_token",
        lambda cookie, token: cookie == "valid-session" and token == "valid-csrf",
    )

    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        client.cookies.set(auth._resolve_cookie_name(), "valid-session")
        with pytest.raises(WebSocketDisconnect) as exc:
            with client.websocket_connect(
                "/api/chat/stream?stream_id=stream-1",
                subprotocols=["ares-v1"],
                headers={"origin": "http://testserver"},
            ):
                pass
        assert exc.value.code == 4403

        with client.websocket_connect(
            "/api/chat/stream?stream_id=stream-1",
            subprotocols=["ares-v1", "ares.csrf.valid-csrf"],
            headers={"origin": "http://testserver"},
        ) as stream:
            assert stream.accepted_subprotocol == "ares-v1"
            assert stream.receive_json()["event"] == "token"


def test_realtime_service_reuses_existing_stream_channel(monkeypatch):
    from api.config import STREAMS, STREAMS_LOCK, StreamChannel

    service = RealtimeService()
    channel = StreamChannel()
    channel.put_nowait(("token", {"text": "existing"}, "stream-real:1"))
    monkeypatch.setattr(service, "authorize_stream", lambda *_args, **_kwargs: "session-real")
    monkeypatch.setattr(
        service,
        "_session_for_profile",
        lambda *_args, **_kwargs: SimpleNamespace(
            session_id="session-real",
            ares_backend="hermes_local",
            profile="default",
        ),
    )
    with STREAMS_LOCK:
        STREAMS["stream-real"] = channel
    try:
        subscription = service.chat_subscription("stream-real", profile=None)
        assert subscription is not None
        assert subscription.subscriber.get_nowait() == (
            "token",
            {"text": "existing"},
            "stream-real:1",
        )
        subscription.close()
        assert subscription.subscriber not in channel._subscribers
    finally:
        with STREAMS_LOCK:
            STREAMS.pop("stream-real", None)


def test_fastapi_websocket_streams_tokens_from_real_channel(tmp_path, monkeypatch):
    from api.config import STREAMS, STREAMS_LOCK, StreamChannel

    frontend = tmp_path / "dist"
    frontend.mkdir()
    (frontend / "index.html").write_text("<div id='root'></div>", encoding="utf-8")
    service = RealtimeService()
    monkeypatch.setattr(service, "authorize_stream", lambda *_args, **_kwargs: "session-real")
    monkeypatch.setattr(
        service,
        "_session_for_profile",
        lambda *_args, **_kwargs: SimpleNamespace(
            session_id="session-real",
            ares_backend="hermes_local",
            profile="default",
        ),
    )
    channel = StreamChannel()
    channel.put_nowait(("token", {"text": "live"}, "stream-real:1"))
    channel.put_nowait(("stream_end", {"status": "completed"}, "stream-real:2"))
    with STREAMS_LOCK:
        STREAMS["stream-real"] = channel
    try:
        application = create_app(frontend_root=frontend, realtime_service=service)
        with TestClient(application, client=("127.0.0.1", 50000)) as client:
            with websocket(client, "/api/chat/stream?stream_id=stream-real") as stream:
                token = stream.receive_json()
                terminal = stream.receive_json()
        assert token["event"] == "token"
        assert token["data"] == {"text": "live"}
        assert terminal["event"] == "stream_end"
    finally:
        with STREAMS_LOCK:
            STREAMS.pop("stream-real", None)


def test_realtime_service_replays_run_journal_after_cursor(tmp_path, monkeypatch):
    from api import run_journal

    monkeypatch.setattr(run_journal, "_default_session_dir", lambda: tmp_path)
    run_journal.append_run_event(
        "session-real",
        "stream-real",
        "token",
        {"text": "old"},
        session_dir=tmp_path,
    )
    run_journal.append_run_event(
        "session-real",
        "stream-real",
        "token",
        {"text": "new"},
        session_dir=tmp_path,
    )

    service = RealtimeService()
    monkeypatch.setattr(
        service,
        "_session_for_profile",
        lambda *_args, **_kwargs: SimpleNamespace(
            session_id="session-real",
            ares_backend="hermes_local",
            profile="default",
        ),
    )
    replay = service.replay_chat("stream-real", after_event_id="stream-real:1")

    assert [(event["event_id"], event["payload"]["text"]) for event in replay] == [
        ("stream-real:2", "new")
    ]


def test_blocking_runtime_queue_read_yields_to_event_loop(monkeypatch):
    from fastapi_app.routers import realtime as realtime_router

    monkeypatch.setattr(realtime_router, "_HEARTBEAT_SECONDS", 0.5)
    runtime_queue: queue.Queue = queue.Queue()

    async def exercise():
        pending_read = asyncio.create_task(_queue_get(runtime_queue))
        await asyncio.sleep(0)
        event_loop_progress = []
        asyncio.get_running_loop().call_soon(event_loop_progress.append, "available")
        await asyncio.sleep(0.01)
        assert event_loop_progress == ["available"]
        runtime_queue.put(("token", {"text": "async"}, "stream-real:3"))
        return await pending_read

    assert asyncio.run(exercise()) == (
        "token",
        {"text": "async"},
        "stream-real:3",
    )
