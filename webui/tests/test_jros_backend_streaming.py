from __future__ import annotations

import sys
import types


def test_jros_backend_selects_real_jros_worker_without_presence_ping(monkeypatch):
    from api import backend_selector, routes

    def fake_get_config():
        return {"ares_backend": "jros"}

    fake_bridge = types.ModuleType("api.jros_bridge")

    def fake_run_jros_streaming(*args, **kwargs):  # pragma: no cover - identity only
        return None

    fake_bridge.run_jros_streaming = fake_run_jros_streaming
    setattr(fake_bridge, "is_jros_bridge_available", lambda: True)
    monkeypatch.setitem(sys.modules, "api.jros_bridge", fake_bridge)
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


def test_jros_repo_root_honors_ares_jros_dir_override(monkeypatch, tmp_path):
    from api import jros_bridge

    override = tmp_path / "custom-jros"
    override.mkdir()
    monkeypatch.setenv("ARES_JROS_DIR", str(override))
    assert jros_bridge._jros_repo_root() == override.resolve()


def test_jros_instance_name_reads_runtime_active_instance(monkeypatch, tmp_path):
    from api import jros_paths

    home = tmp_path / "jaeger-home"
    active_dir = home / ".jaeger_os"
    instance_dir = active_dir / "instances" / "jros-dev"
    instance_dir.mkdir(parents=True)
    (active_dir / "active_instance").write_text("jros-dev\n", encoding="utf-8")
    config_path = instance_dir / "config.yaml"
    config_path.write_text("instance_name: jros-dev\n", encoding="utf-8")

    monkeypatch.setenv("ARES_JAEGER_HOME", str(home))
    monkeypatch.delenv("JAEGER_HOME", raising=False)
    monkeypatch.delenv("ARES_JROS_INSTANCE", raising=False)
    monkeypatch.delenv("JAEGER_INSTANCE_NAME", raising=False)
    monkeypatch.delenv("ARES_JROS_CONFIG_PATH", raising=False)
    monkeypatch.delenv("JAEGER_INSTANCE_DIR", raising=False)

    assert jros_paths.jros_instance_name() == "jros-dev"
    assert jros_paths.jros_config_path() == config_path.resolve()


def test_jros_client_appends_resolved_instance_to_bridge_command(monkeypatch, tmp_path):
    from api.jros_client import JrosClient

    home = tmp_path / "jaeger-home"
    (home / ".jaeger_os").mkdir(parents=True)
    (home / ".jaeger_os" / "active_instance").write_text("jros-dev\n", encoding="utf-8")
    launcher = home / "jaeger"
    launcher.write_text("#!/bin/sh\n", encoding="utf-8")
    launcher.chmod(0o755)

    monkeypatch.setenv("ARES_JAEGER_HOME", str(home))
    monkeypatch.delenv("JAEGER_HOME", raising=False)
    monkeypatch.delenv("ARES_JROS_INSTANCE", raising=False)
    monkeypatch.delenv("JAEGER_INSTANCE_NAME", raising=False)

    client = JrosClient()
    assert client._command == [str(launcher.resolve()), "bridge", "jros-dev"]


def test_jros_client_appends_instance_to_explicit_jaeger_bridge_command(monkeypatch, tmp_path):
    from api.jros_client import JrosClient

    launcher = tmp_path / "jaeger"
    launcher.write_text("#!/bin/sh\n", encoding="utf-8")
    launcher.chmod(0o755)
    monkeypatch.setenv("ARES_JROS_INSTANCE", "jros-dev")

    client = JrosClient(command=[str(launcher), "bridge"])
    assert client._command == [str(launcher), "bridge", "jros-dev"]


def test_jros_bridge_runs_voice_turn_and_persists_session(monkeypatch):
    from api import config
    from api.config import create_stream_channel, register_stream_owner
    from api.models import Session
    from api import jros_bridge

    sid = "jrosbridge2"
    stream_id = "stream-jrosbridge2"
    session = Session(session_id=sid, messages=[])
    session.active_stream_id = stream_id
    session.pending_user_message = "hello jros"
    session.save()

    stream = create_stream_channel()
    register_stream_owner(stream_id, sid)
    with config.STREAMS_LOCK:
        config.STREAMS[stream_id] = stream

    calls = []

    class FakeJrosClient:
        def turn(self, text, session="", on_event=None, on_request=None):
            calls.append((text, session))
            if on_event:
                on_event({"type": "tool", "name": "demo", "status": "ok"})
            return {"text": "JROS says hi", "error": None}

    monkeypatch.setattr(jros_bridge, "_get_jros_client", lambda: FakeJrosClient())

    jros_bridge.run_jros_streaming(
        sid,
        "hello jros",
        "test-model",
        "/tmp",
        stream_id,
        [],
        model_provider="test-provider",
    )

    assert calls == [("hello jros", f"webui:{sid}")]
    events = [item[0] for item in stream._offline_buffer]
    assert "tool" in events
    assert any(
        item[0] == "token" and item[1] == {"text": "JROS says hi"}
        for item in stream._offline_buffer
    )
    assert events[-2:] == ["done", "stream_end"]

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
