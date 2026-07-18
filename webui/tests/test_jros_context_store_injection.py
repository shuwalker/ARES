"""Context Store injection into JaegerAI ("jros") gateway turns.

Uses the same fake-HTTP-gateway technique as test_jros_backend_streaming.py's
_FakeJrosGateway, trimmed to just what's needed here: a health check plus a
POST handler that captures the request body so the injected system message
can be asserted on.
"""
from __future__ import annotations

import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from api import context_store


class _FakeJrosGateway(BaseHTTPRequestHandler):
    seen: list[dict] = []

    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path.rstrip("/") == "/v1/health":
            body = json.dumps({"ok": True, "backend": "jros", "booted": True}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(404)
        self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length") or 0)
        payload = json.loads(self.rfile.read(length).decode("utf-8"))
        type(self).seen.append({"path": self.path, "body": payload})
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        frames = [
            'data: ' + json.dumps({
                "object": "chat.completion.chunk",
                "choices": [{"index": 0, "delta": {"role": "assistant", "content": "ack"}, "finish_reason": "stop"}],
            }) + "\n\n",
            "data: [DONE]\n\n",
        ]
        for frame in frames:
            self.wfile.write(frame.encode("utf-8"))
        self.wfile.flush()


def _start_fake_gateway():
    server = ThreadingHTTPServer(("127.0.0.1", 0), _FakeJrosGateway)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    return server, f"http://127.0.0.1:{server.server_address[1]}"


def _run_turn(monkeypatch, sid: str) -> dict:
    from api import config
    from api.config import create_stream_channel, register_stream_owner
    from api.models import Session
    from api import jros_gateway_chat

    server, base = _start_fake_gateway()
    _FakeJrosGateway.seen = []
    monkeypatch.setenv("ARES_JROS_GATEWAY_URL", base)
    try:
        stream_id = f"stream-{sid}"
        session = Session(session_id=sid, messages=[])
        session.active_stream_id = stream_id
        session.pending_user_message = "hello jros"
        session.save()

        stream = create_stream_channel()
        register_stream_owner(stream_id, sid)
        with config.STREAMS_LOCK:
            config.STREAMS[stream_id] = stream

        jros_gateway_chat.run_jros_streaming(
            sid, "hello jros", "test-model", "/tmp", stream_id, [],
            model_provider="test-provider",
        )
        chat_calls = [c for c in _FakeJrosGateway.seen if c["path"].endswith("/chat/completions")]
        assert len(chat_calls) == 1
        return chat_calls[0]["body"]
    finally:
        server.shutdown()
        server.server_close()


def test_context_store_chunks_prepended_as_system_message(monkeypatch, tmp_path):
    chunk = context_store.RetrievedChunk(
        text="Use FastAPI for the backend.", source_key="memory", source_type="memory",
        path="MEMORY.md", heading="", distance=0.1,
    )
    monkeypatch.setattr("api.context_store.retrieve", lambda query, **kwargs: [chunk])

    body = _run_turn(monkeypatch, "jros-ctx-1")

    assert body["messages"][0]["role"] == "system"
    assert "FastAPI" in body["messages"][0]["content"]
    assert body["messages"][-1] == {"role": "user", "content": "hello jros"}


def test_no_injection_when_retrieval_returns_empty(monkeypatch):
    monkeypatch.setattr("api.context_store.retrieve", lambda query, **kwargs: [])

    body = _run_turn(monkeypatch, "jros-ctx-2")

    assert body["messages"] == [{"role": "user", "content": "hello jros"}]


def test_no_injection_when_retrieval_raises(monkeypatch):
    def boom(query, **kwargs):
        raise RuntimeError("context store exploded")

    monkeypatch.setattr("api.context_store.retrieve", boom)

    # Must not raise or block the turn -- the whole point of the degrade contract.
    body = _run_turn(monkeypatch, "jros-ctx-3")

    assert body["messages"] == [{"role": "user", "content": "hello jros"}]


def test_local_bridge_path_never_calls_context_store_retrieve(monkeypatch, tmp_path):
    """Regression guard for the documented v1 scoping gap: the local-bridge
    fallback path (no explicit gateway URL configured) has no system-prompt
    injection point today, so retrieve() must never be called on that path."""
    from api import config
    from api.config import create_stream_channel, register_stream_owner
    from api.models import Session
    from api import jros_gateway_chat

    called = {"count": 0}

    def spy_retrieve(query, **kwargs):
        called["count"] += 1
        return []

    monkeypatch.setattr("api.context_store.retrieve", spy_retrieve)
    monkeypatch.delenv("ARES_JROS_GATEWAY_URL", raising=False)
    monkeypatch.setattr(jros_gateway_chat, "jros_gateway_base_url", lambda cfg: "http://127.0.0.1:1")
    monkeypatch.setattr(jros_gateway_chat, "local_jros_root", lambda: tmp_path)
    monkeypatch.setattr(
        jros_gateway_chat, "_run_local_jros_turn",
        lambda msg_text, session_id, cancel_event, put_jros_event, stream_id: ("local reply", "", []),
    )

    sid = "jros-ctx-local"
    stream_id = f"stream-{sid}"
    session = Session(session_id=sid, messages=[])
    session.active_stream_id = stream_id
    session.pending_user_message = "hello jros"
    session.save()

    stream = create_stream_channel()
    register_stream_owner(stream_id, sid)
    with config.STREAMS_LOCK:
        config.STREAMS[stream_id] = stream

    jros_gateway_chat.run_jros_streaming(
        sid, "hello jros", "test-model", "/tmp", stream_id, [],
        model_provider="test-provider",
    )

    assert called["count"] == 0
