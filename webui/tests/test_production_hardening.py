"""Focused regression tests for the Phase 5 security and readiness contracts."""

from __future__ import annotations

import json
from pathlib import Path
from types import SimpleNamespace

from fastapi.testclient import TestClient

from fastapi_app.adapters.frameworks import GeminiCloudAdapter
from fastapi_app.errors import CoreApiError
from fastapi_app.main import create_app
from fastapi_app.request_context import (
    RequestIdentity,
    require_identity,
    require_mutation_identity,
)


IDENTITY = RequestIdentity(session_cookie=None, profile="default", auth_enabled=False)


class StaticRegistry:
    def __init__(self, connections, *, selected=None):
        self.connections = connections
        self.selected = selected

    def connection_records(self, *, profile, session=None):
        return {"selected": self.selected, "connections": self.connections}


def _app(tmp_path: Path, registry) -> object:
    frontend = tmp_path / "dist"
    frontend.mkdir(parents=True)
    (frontend / "index.html").write_text("<div id='root'></div>", encoding="utf-8")
    app = create_app(frontend_root=frontend, adapter_registry=registry)
    app.dependency_overrides[require_identity] = lambda: IDENTITY
    app.dependency_overrides[require_mutation_identity] = lambda: IDENTITY
    return app


def test_readiness_requires_a_connected_execution_runtime(tmp_path, monkeypatch):
    monkeypatch.setattr("api.profiles.get_active_profile_name", lambda: "default")
    monkeypatch.setattr("api.config.load_settings", lambda: {"onboarding_completed": True})
    registry = StaticRegistry(
        [
            {
                "id": "mcp",
                "kind": "tool",
                "health": {"state": "connected", "available": True},
                "capabilities": ["tool.discovery"],
            },
            {
                "id": "offline-runtime",
                "kind": "runtime",
                "health": {"state": "offline", "available": False},
                "capabilities": ["conversation"],
            },
        ]
    )
    app = _app(tmp_path, registry)

    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        response = client.get("/api/readiness")

    assert response.status_code == 200
    assert response.json()["connection_ready"] is False
    assert response.json()["execution_available"] is False
    assert response.json()["capabilities"] == []


def test_readiness_requires_the_elected_runtime_not_just_any_runtime(tmp_path, monkeypatch):
    monkeypatch.setattr("api.profiles.get_active_profile_name", lambda: "default")
    monkeypatch.setattr("api.config.load_settings", lambda: {"onboarding_completed": True})
    connected = {
        "id": "connected-runtime",
        "kind": "runtime",
        "health": {"state": "connected", "available": True},
        "capabilities": ["conversation", "tool.use"],
    }
    app = _app(tmp_path, StaticRegistry([connected], selected=None))

    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        response = client.get("/api/readiness")

    assert response.status_code == 200
    assert response.json()["connection_ready"] is False
    assert response.json()["selected_connection"] is None

    app = _app(tmp_path / "selected", StaticRegistry([connected], selected="connected-runtime"))
    with TestClient(app, client=("127.0.0.1", 50001)) as client:
        response = client.get("/api/readiness")

    assert response.status_code == 200
    assert response.json()["connection_ready"] is True
    assert response.json()["execution_available"] is True
    assert response.json()["capabilities"] == ["conversation", "tool.use"]


def test_readiness_does_not_treat_implicit_default_name_as_saved_profile(tmp_path, monkeypatch):
    monkeypatch.setattr("api.profiles.get_active_profile_name", lambda: "default")
    monkeypatch.setattr("api.config.load_settings", lambda: {})
    app = _app(tmp_path, StaticRegistry([], selected=None))

    with TestClient(app, client=("127.0.0.1", 50002)) as client:
        response = client.get("/api/readiness")

    assert response.status_code == 200
    assert response.json()["profile"] == "default"
    assert response.json()["profile_ready"] is False


def test_discovery_apply_is_guarded_by_mutation_identity(tmp_path):
    app = _app(tmp_path, StaticRegistry([]))

    def reject_mutation():
        raise CoreApiError(403, "mutation rejected")

    app.dependency_overrides[require_mutation_identity] = reject_mutation
    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        response = client.post("/api/discover/frameworks/apply")

    assert response.status_code == 403
    assert response.json()["error"] == "mutation rejected"


def test_cli_environment_does_not_forward_unrelated_secrets(monkeypatch):
    from api.backends.cli_backends import _minimal_host_environment
    from api.config import _clear_thread_env, _set_thread_env, _thread_ctx

    monkeypatch.setenv("UNRELATED_SECRET", "must-not-leak")
    monkeypatch.setenv("OPENAI_API_KEY", "host-key")
    previous_block = bool(getattr(_thread_ctx, "block_process_env_fallback", False))
    try:
        _set_thread_env(OPENAI_API_KEY="profile-key")
        _thread_ctx.block_process_env_fallback = True
        env = _minimal_host_environment(("OPENAI_API_KEY",))
    finally:
        _thread_ctx.block_process_env_fallback = previous_block
        _clear_thread_env()

    assert env["OPENAI_API_KEY"] == "profile-key"
    assert "UNRELATED_SECRET" not in env


def test_gemini_probe_uses_header_not_query_string(monkeypatch):
    import fastapi_app.adapters.frameworks as frameworks

    captured = {}

    class Response:
        status = 200

        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

    def urlopen(request, timeout):
        captured["url"] = request.full_url
        captured["headers"] = dict(request.header_items())
        captured["timeout"] = timeout
        return Response()

    monkeypatch.setattr(frameworks, "_credential", lambda _name: "top-secret-key")
    monkeypatch.setattr(frameworks.urllib.request, "urlopen", urlopen)

    health = GeminiCloudAdapter().check_health(profile="default")

    assert health.available is True
    assert "top-secret-key" not in captured["url"]
    assert captured["headers"]["X-goog-api-key"] == "top-secret-key"
    assert captured["timeout"] == 5


def test_cli_and_cloud_backends_use_their_selected_runtime_worker():
    from api.backends.base import run_agentic_backend_streaming
    from api.backends.cli_backends import ClaudeLocalBackend, OpenAICloudBackend

    assert ClaudeLocalBackend().get_worker_target()[0] is run_agentic_backend_streaming
    assert OpenAICloudBackend().get_worker_target()[0] is run_agentic_backend_streaming


def test_ollama_stream_worker_uses_broadcast_channel_and_skips_malformed_json(
    monkeypatch,
):
    """A malformed Ollama line must not crash or strand the active stream."""
    from api.backends.cli_backends import run_ollama_streaming
    from api.config import CANCEL_FLAGS, STREAMS, STREAMS_LOCK, StreamChannel
    import api.models as models
    import api.run_journal as run_journal
    import api.streaming as streaming
    import requests

    stream_id = "production-hardening-ollama"
    session_id = "production-hardening-session"
    channel = StreamChannel()
    session = SimpleNamespace(
        messages=[],
        active_stream_id=stream_id,
        pending_user_message="hello",
        pending_attachments=[],
        pending_started_at=1,
        pending_user_source="webui",
        save=lambda *args, **kwargs: None,
    )

    class Journal:
        sequence = 0

        def __init__(self, *_args):
            pass

        def append_sse_event(self, _event, _data):
            self.sequence += 1
            return {"event_id": f"{stream_id}:{self.sequence}"}

        def close(self):
            pass

    class Response:
        def __enter__(self):
            return self

        def __exit__(self, *_args):
            return False

        def raise_for_status(self):
            pass

        def iter_lines(self):
            yield b"not-json"
            yield json.dumps({"response": "hello", "done": False}).encode()
            yield json.dumps({"response": " world", "done": True}).encode()

    request_options = {}
    def fake_post(*_args, **kwargs):
        request_options.update(kwargs.get("json", {}).get("options", {}))
        return Response()
    monkeypatch.setattr(requests, "post", fake_post)
    monkeypatch.setattr(run_journal, "RunJournalWriter", Journal)
    monkeypatch.setattr(models, "get_session", lambda _session_id: session)
    monkeypatch.setattr(streaming, "register_active_run", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(streaming, "unregister_active_run", lambda *_args, **_kwargs: None)
    monkeypatch.setattr(streaming, "unregister_stream_owner", lambda *_args, **_kwargs: None)

    with STREAMS_LOCK:
        STREAMS[stream_id] = channel
    try:
        run_ollama_streaming(
            session_id,
            "hello",
            "test-model",
            "/tmp",
            stream_id,
            [],
        )
        subscriber = channel.subscribe()
        events = []
        while not subscriber.empty():
            events.append(subscriber.get_nowait())
    finally:
        with STREAMS_LOCK:
            STREAMS.pop(stream_id, None)
            CANCEL_FLAGS.pop(stream_id, None)

    assert [event[0] for event in events] == ["token", "token", "stream_end", "done"]
    assert [event[1]["text"] for event in events[:2]] == ["hello", " world"]
    assert session.messages[-1]["content"] == "hello world"
    assert session.active_stream_id is None
    assert request_options["num_predict"] == 2048


def test_ares_owned_schedule_store_round_trips_skills_with_private_permissions(
    tmp_path,
):
    from api.profiles import cron_profile_context_for_home
    from api.schedule_jobs import create_job, list_jobs

    with cron_profile_context_for_home(tmp_path):
        created = create_job(
            name="skills-roundtrip",
            prompt="use the elected runtime",
            schedule="0 9 * * *",
            skills=["memory-search"],
        )
        listed = list_jobs(include_disabled=True)
        jobs_file = tmp_path / "cron" / "jobs.json"

    assert next(job for job in listed if job["id"] == created["id"])["skills"] == [
        "memory-search"
    ]
    assert jobs_file.stat().st_mode & 0o777 == 0o600
    assert jobs_file.parent.stat().st_mode & 0o777 == 0o700


def test_schedule_execution_refuses_to_invent_a_default_runtime(monkeypatch):
    from api.schedule_scheduler import run_job

    monkeypatch.setattr("api.backend_selector.get_active_backend", lambda _config: "")
    monkeypatch.setattr("api.config.get_config", lambda: {})

    success, output, final_response, error = run_job(
        {"id": "schedule-1", "prompt": "hello"}
    )

    assert success is False
    assert output == "No default external runtime is selected."
    assert final_response == ""
    assert error == output
