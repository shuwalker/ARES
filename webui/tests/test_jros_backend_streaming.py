"""JROS backend — worker selection, the gateway chat bridge, and the
in-process fallback.

The JROS backend prefers a JROS gateway server (`jaeger gateway`) over
HTTP, mirroring the Hermes Gateway bridge; with no gateway reachable and
ARES_JROS_DIR pointing at a local checkout, it boots JROS in-process
instead. These tests pin:
  * routes still dispatch the jros backend to the gateway worker,
  * hybrid still falls through to the normal Hermes worker,
  * gateway URL resolution (env > config > localhost default),
  * a full turn against a REAL (in-test, faked-JROS) HTTP gateway —
    SSE relay, tool events, session persistence, stream teardown,
  * the in-process fallback: runs the turn locally, turns the instance
    lock and missing-instance cases into actionable errors (never the
    interactive wizard), and never runs while a gateway is up,
  * an offline gateway with no local checkout surfaces an actionable
    apperror,
  * backend availability: gateway health → mode "gateway", local
    checkout only → mode "local".
"""
from __future__ import annotations

import json
import sys
import threading
import types
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


def test_jros_backend_selects_gateway_worker_without_health_ping(monkeypatch):
    from api import backend_selector, routes

    def fake_get_config():
        return {"ares_backend": "jros"}

    fake_bridge = types.ModuleType("api.jros_gateway_chat")

    def fake_run_jros_streaming(*args, **kwargs):  # pragma: no cover - identity only
        return None

    fake_bridge.run_jros_streaming = fake_run_jros_streaming
    monkeypatch.setitem(sys.modules, "api.jros_gateway_chat", fake_bridge)
    monkeypatch.setattr(routes, "get_config", fake_get_config)
    monkeypatch.setattr(routes, "webui_gateway_chat_enabled", lambda _cfg: False)
    monkeypatch.setattr(backend_selector, "is_jros_available", lambda: False)

    worker, is_gateway, is_jros = routes._select_chat_worker_target()

    assert worker is fake_run_jros_streaming
    assert is_gateway is False
    assert is_jros is True


def test_hybrid_backend_keeps_normal_hermes_worker(monkeypatch):
    from api import routes

    monkeypatch.setattr(routes, "get_config", lambda: {"ares_backend": "hybrid"})
    monkeypatch.setattr(routes, "webui_gateway_chat_enabled", lambda _cfg: False)

    worker, is_gateway, is_jros = routes._select_chat_worker_target()

    assert worker is routes._run_agent_streaming
    assert is_gateway is False
    assert is_jros is False


def test_gateway_url_resolution_env_config_default(monkeypatch):
    from api import jros_gateway_chat as jgc

    monkeypatch.delenv("ARES_JROS_GATEWAY_URL", raising=False)
    assert jgc.jros_gateway_base_url() == jgc.DEFAULT_JROS_GATEWAY_URL
    assert jgc.jros_gateway_base_url({"jros_gateway_url": "http://pc.lan:9000/"}) == "http://pc.lan:9000"
    monkeypatch.setenv("ARES_JROS_GATEWAY_URL", "http://other:8643/")
    assert jgc.jros_gateway_base_url({"jros_gateway_url": "http://pc.lan:9000"}) == "http://other:8643"


def test_jros_repo_root_still_honors_ares_jros_dir_for_characters(monkeypatch, tmp_path):
    from api import characters

    override = tmp_path / "custom-jros"
    override.mkdir()
    monkeypatch.setenv("ARES_JROS_DIR", str(override))
    assert characters._jros_repo_root() == override.resolve()


class _FakeJrosGateway(BaseHTTPRequestHandler):
    """A canned `jaeger gateway`: health + one streamed turn in the same
    SSE dialect the real jaeger_os/interfaces/http_gateway.py emits."""

    seen: list[dict] = []

    def log_message(self, *args):  # keep pytest output clean
        pass

    def do_GET(self):
        if self.path.rstrip("/") == "/v1/health":
            body = json.dumps({"ok": True, "backend": "jros", "booted": True,
                               "model": "fake-model", "provider": "local",
                               "instance": "test"}).encode()
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
        if self.path.rstrip("/") == "/v1/reset":
            body = b'{"ok": true, "rebooting": true}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.end_headers()
        frames = [
            'event: jros.status\ndata: {"status": "running", "booted": true}\n\n',
            'event: hermes.tool.progress\n'
            'data: {"event": "tool.completed", "tool": "jros", "status": "completed", "label": "  \\u25b8 demo(x)"}\n\n',
            'data: ' + json.dumps({
                "object": "chat.completion.chunk",
                "choices": [{"index": 0,
                             "delta": {"role": "assistant", "content": "JROS says hi"},
                             "finish_reason": "stop"}],
                "usage": {"prompt_tokens": 5, "completion_tokens": 3},
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


def test_jros_gateway_turn_streams_and_persists_session(monkeypatch):
    from api import config
    from api.config import create_stream_channel, register_stream_owner
    from api.models import Session
    from api import jros_gateway_chat

    server, base = _start_fake_gateway()
    _FakeJrosGateway.seen = []
    monkeypatch.setenv("ARES_JROS_GATEWAY_URL", base)
    try:
        sid = "jrosgw1"
        stream_id = "stream-jrosgw1"
        session = Session(session_id=sid, messages=[])
        session.active_stream_id = stream_id
        session.pending_user_message = "hello jros"
        session.save()

        stream = create_stream_channel()
        register_stream_owner(stream_id, sid)
        with config.STREAMS_LOCK:
            config.STREAMS[stream_id] = stream

        jros_gateway_chat.run_jros_streaming(
            sid,
            "hello jros",
            "test-model",
            "/tmp",
            stream_id,
            [],
            model_provider="test-provider",
        )

        # The gateway saw one chat turn keyed to this WebUI session.
        chat_calls = [c for c in _FakeJrosGateway.seen if c["path"].endswith("/chat/completions")]
        assert len(chat_calls) == 1
        assert chat_calls[0]["body"]["user"] == f"webui:{sid}"
        assert chat_calls[0]["body"]["messages"][-1]["content"] == "hello jros"

        events = [item[0] for item in stream._offline_buffer]
        assert "tool" in events
        assert any(
            item[0] == "token" and item[1] == {"text": "JROS says hi"}
            for item in stream._offline_buffer
        )
        assert events[-2:] == ["done", "stream_end"]
        done_payload = next(item[1] for item in stream._offline_buffer if item[0] == "done")
        assert done_payload["usage"]["input_tokens"] == 5
        assert done_payload["usage"]["output_tokens"] == 3

        saved = Session.load(sid)
        assert saved.active_stream_id is None
        assert saved.pending_user_message is None
        assert [m["role"] for m in saved.messages] == ["user", "assistant"]
        assert saved.messages[-1]["content"] == "JROS says hi"
        assert saved.messages[-1]["backend"] == "jros"
        assert saved.messages[-1]["model_provider"] == "test-provider"
        assert saved.model == "test-model"
        assert saved.model_provider == "test-provider"
        assert stream_id not in config.STREAMS
        assert stream_id not in config.CANCEL_FLAGS
    finally:
        server.shutdown()
        server.server_close()


def test_offline_gateway_surfaces_actionable_apperror(monkeypatch):
    from api import config
    from api.config import create_stream_channel, register_stream_owner
    from api.models import Session
    from api import jros_gateway_chat

    # A port nothing listens on — connection refused, fast. No local
    # checkout either, so the in-process fallback must not trigger.
    monkeypatch.setenv("ARES_JROS_GATEWAY_URL", "http://127.0.0.1:1")
    monkeypatch.delenv("ARES_JROS_DIR", raising=False)
    sid = "jrosgw-down"
    stream_id = "stream-jrosgw-down"
    session = Session(session_id=sid, messages=[])
    session.active_stream_id = stream_id
    session.pending_user_message = "hello"
    session.save()

    stream = create_stream_channel()
    register_stream_owner(stream_id, sid)
    with config.STREAMS_LOCK:
        config.STREAMS[stream_id] = stream

    jros_gateway_chat.run_jros_streaming(sid, "hello", "m", "/tmp", stream_id, [])

    apperrors = [item[1] for item in stream._offline_buffer if item[0] == "apperror"]
    assert len(apperrors) == 1
    assert apperrors[0]["type"] == "jros_gateway_offline"
    assert "jaeger gateway" in apperrors[0]["hint"]
    # No assistant message was fabricated for the failed turn.
    saved = Session.load(sid)
    assert all(m.get("role") != "assistant" for m in saved.messages)


def test_backend_availability_follows_gateway_health(monkeypatch):
    from api import backend_selector

    server, base = _start_fake_gateway()
    monkeypatch.setenv("ARES_JROS_GATEWAY_URL", base)
    try:
        monkeypatch.setattr(backend_selector, "_jros_available_cache", None)
        monkeypatch.setattr(backend_selector, "_jros_gateway_info", {})
        assert backend_selector.is_jros_available() is True
        status = backend_selector.backend_status()
        assert status["jros"] is True
        assert status["jros_model"] == "fake-model"
        assert status["jros_booted"] is True
    finally:
        server.shutdown()
        server.server_close()

    monkeypatch.setenv("ARES_JROS_GATEWAY_URL", "http://127.0.0.1:1")
    monkeypatch.delenv("ARES_JROS_DIR", raising=False)
    monkeypatch.setattr(backend_selector, "_jros_available_cache", None)
    assert backend_selector.is_jros_available() is False
    assert backend_selector.backend_status()["jros"] is False


def test_reset_jros_boot_posts_reset_and_swallows_offline(monkeypatch):
    from api import jros_gateway_chat

    server, base = _start_fake_gateway()
    _FakeJrosGateway.seen = []
    monkeypatch.setenv("ARES_JROS_GATEWAY_URL", base)
    try:
        jros_gateway_chat.reset_jros_boot()
        assert [c["path"] for c in _FakeJrosGateway.seen] == ["/v1/reset"]
    finally:
        server.shutdown()
        server.server_close()

    monkeypatch.setenv("ARES_JROS_GATEWAY_URL", "http://127.0.0.1:1")
    jros_gateway_chat.reset_jros_boot()  # must not raise


# ── in-process fallback (no gateway, local checkout) ─────────────────────

def _setup_stream(sid, stream_id, pending="hello jros"):
    from api import config
    from api.config import create_stream_channel, register_stream_owner
    from api.models import Session

    session = Session(session_id=sid, messages=[])
    session.active_stream_id = stream_id
    session.pending_user_message = pending
    session.save()
    stream = create_stream_channel()
    register_stream_owner(stream_id, sid)
    with config.STREAMS_LOCK:
        config.STREAMS[stream_id] = stream
    return stream


def _local_checkout(monkeypatch, tmp_path):
    """A directory that looks like a JROS checkout, wired to ARES_JROS_DIR,
    with the gateway pointed at a dead port so the fallback path runs."""
    (tmp_path / "jaeger_os").mkdir()
    monkeypatch.setenv("ARES_JROS_DIR", str(tmp_path))
    monkeypatch.setenv("ARES_JROS_GATEWAY_URL", "http://127.0.0.1:1")


def test_local_fallback_runs_turn_when_no_gateway(monkeypatch, tmp_path):
    from api import jros_gateway_chat
    from api.models import Session

    _local_checkout(monkeypatch, tmp_path)
    monkeypatch.setattr(jros_gateway_chat, "_BOOT", None)
    monkeypatch.setattr(
        jros_gateway_chat, "_boot_jros",
        lambda: types.SimpleNamespace(client=object()),
    )
    calls = []
    fake_main = types.ModuleType("jaeger_os.main")

    def fake_run_for_voice(client, text, session_key=None):
        calls.append((text, session_key))
        return {"text": "local JROS says hi", "error": None,
                "tool_activity": ["  ▸ demo(x)"], "elapsed_s": 0.01}

    fake_main.run_for_voice = fake_run_for_voice
    monkeypatch.setitem(sys.modules, "jaeger_os.main", fake_main)

    sid, stream_id = "jroslocal1", "stream-jroslocal1"
    stream = _setup_stream(sid, stream_id)
    jros_gateway_chat.run_jros_streaming(
        sid, "hello jros", "test-model", "/tmp", stream_id, [],
        model_provider="test-provider",
    )

    assert calls == [("hello jros", f"webui:{sid}")]
    events = [item[0] for item in stream._offline_buffer]
    assert "tool" in events
    assert any(
        item[0] == "token" and item[1] == {"text": "local JROS says hi"}
        for item in stream._offline_buffer
    )
    assert events[-2:] == ["done", "stream_end"]
    saved = Session.load(sid)
    assert saved.messages[-1]["content"] == "local JROS says hi"
    assert saved.messages[-1]["backend"] == "jros"


def _fake_jaeger_instance_modules(monkeypatch, *, exists=True):
    """Install the module chain _boot_jros imports, with a controllable
    InstanceLayout.exists()."""
    pkg = types.ModuleType("jaeger_os")
    core = types.ModuleType("jaeger_os.core")
    inst_pkg = types.ModuleType("jaeger_os.core.instance")
    inst = types.ModuleType("jaeger_os.core.instance.instance")
    inst.default_instance_name = lambda: "testinst"
    inst.resolve_instance_dir = lambda name: f"/nonexistent/{name}"
    inst.InstanceLayout = lambda root: types.SimpleNamespace(
        root=root, exists=lambda: exists)
    for name, mod in (("jaeger_os", pkg), ("jaeger_os.core", core),
                      ("jaeger_os.core.instance", inst_pkg),
                      ("jaeger_os.core.instance.instance", inst)):
        monkeypatch.setitem(sys.modules, name, mod)


def test_local_fallback_lock_error_is_actionable(monkeypatch, tmp_path):
    from api import jros_gateway_chat

    _local_checkout(monkeypatch, tmp_path)
    monkeypatch.setattr(jros_gateway_chat, "_BOOT", None)
    _fake_jaeger_instance_modules(monkeypatch, exists=True)
    fake_main = types.ModuleType("jaeger_os.main")

    def locked_boot(**kwargs):
        raise RuntimeError("instance 'testinst' is locked by pid 7 (still running).")

    fake_main.boot_for_tui = locked_boot
    monkeypatch.setitem(sys.modules, "jaeger_os.main", fake_main)

    sid, stream_id = "jroslock1", "stream-jroslock1"
    stream = _setup_stream(sid, stream_id)
    jros_gateway_chat.run_jros_streaming(sid, "hi", "m", "/tmp", stream_id, [])

    apperrors = [item[1] for item in stream._offline_buffer if item[0] == "apperror"]
    assert len(apperrors) == 1
    assert apperrors[0]["type"] == "jros_local_error"
    assert "already running" in apperrors[0]["message"]
    assert "jaeger gateway" in apperrors[0]["message"]


def test_local_fallback_missing_instance_says_run_setup(monkeypatch, tmp_path):
    from api import jros_gateway_chat

    _local_checkout(monkeypatch, tmp_path)
    monkeypatch.setattr(jros_gateway_chat, "_BOOT", None)
    _fake_jaeger_instance_modules(monkeypatch, exists=False)
    fake_main = types.ModuleType("jaeger_os.main")

    def wizard_boot(**kwargs):  # the old bridge hung here — must never run
        raise AssertionError("boot_for_tui must not be called without an instance")

    fake_main.boot_for_tui = wizard_boot
    monkeypatch.setitem(sys.modules, "jaeger_os.main", fake_main)

    sid, stream_id = "jrossetup1", "stream-jrossetup1"
    stream = _setup_stream(sid, stream_id)
    jros_gateway_chat.run_jros_streaming(sid, "hi", "m", "/tmp", stream_id, [])

    apperrors = [item[1] for item in stream._offline_buffer if item[0] == "apperror"]
    assert len(apperrors) == 1
    assert "jaeger setup" in apperrors[0]["message"]


def test_gateway_wins_over_local_fallback(monkeypatch, tmp_path):
    from api import jros_gateway_chat
    from api.models import Session

    server, base = _start_fake_gateway()
    _FakeJrosGateway.seen = []
    (tmp_path / "jaeger_os").mkdir()
    monkeypatch.setenv("ARES_JROS_DIR", str(tmp_path))
    monkeypatch.setenv("ARES_JROS_GATEWAY_URL", base)
    monkeypatch.setattr(
        jros_gateway_chat, "_run_local_jros_turn",
        lambda *a, **k: (_ for _ in ()).throw(
            AssertionError("local fallback must not run while the gateway is up")),
    )
    try:
        sid, stream_id = "jrosboth1", "stream-jrosboth1"
        _setup_stream(sid, stream_id)
        jros_gateway_chat.run_jros_streaming(sid, "hello jros", "m", "/tmp", stream_id, [])
        assert any(c["path"].endswith("/chat/completions") for c in _FakeJrosGateway.seen)
        assert Session.load(sid).messages[-1]["content"] == "JROS says hi"
    finally:
        server.shutdown()
        server.server_close()


def test_backend_availability_local_mode_without_gateway(monkeypatch, tmp_path):
    from api import backend_selector

    (tmp_path / "jaeger_os").mkdir()
    monkeypatch.setenv("ARES_JROS_DIR", str(tmp_path))
    monkeypatch.setenv("ARES_JROS_GATEWAY_URL", "http://127.0.0.1:1")
    monkeypatch.setattr(backend_selector, "_jros_available_cache", None)
    monkeypatch.setattr(backend_selector, "_jros_gateway_info", {})
    assert backend_selector.is_jros_available() is True
    status = backend_selector.backend_status()
    assert status["jros"] is True
    assert status["jros_mode"] == "local"
