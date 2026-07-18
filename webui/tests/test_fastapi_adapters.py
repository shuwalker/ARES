"""Phase 2 Step 4 adapter boundary and selection tests."""

from __future__ import annotations

import asyncio
from pathlib import Path
import inspect
from types import SimpleNamespace

from fastapi.testclient import TestClient
import pytest

from fastapi_app.adapters import (
    AdapterError,
    AdapterHealth,
    AdapterRegistry,
    AresAdapter,
    BaseLLMAdapter,
    BaseToolAdapter,
    JaegerAdapter,
    McpToolAdapter,
    ModelDescriptor,
)
from fastapi_app.main import create_app
from fastapi_app.realtime import RealtimeService
from fastapi_app.request_context import (
    RequestIdentity,
    require_identity,
    require_mutation_identity,
)
from fastapi_app.schemas import ChatStart


IDENTITY = RequestIdentity(session_cookie=None, profile="default", auth_enabled=False)


class RecordingAdapter(BaseLLMAdapter):
    adapter_id = "recording"
    display_name = "Recording runtime"

    def __init__(self):
        self.started = []
        self.cancelled = []

    def check_health(self, *, profile):
        return AdapterHealth("connected", True, f"ready:{profile}")

    def capabilities(self, *, profile):
        return ["conversation", f"profile:{profile}"]

    async def stream_chat(self, request, *, session, profile):
        self.started.append((request, session, profile))
        return {"stream_id": "recording-run", "session_id": session.session_id}

    def get_models(self, *, profile):
        return [ModelDescriptor("model-1", "Model One", "provider", self.adapter_id)]

    def subscribe_stream(self, stream_id, *, owner_session_id):
        return None

    def replay_stream(self, stream_id, *, after_event_id=None):
        return []

    def stream_status(self, stream_id):
        return {"active": False, "stream_id": stream_id, "replay_available": True}

    def cancel_stream(self, stream_id):
        self.cancelled.append(stream_id)
        return True


class RecordingTools(BaseToolAdapter):
    adapter_id = "mcp"
    display_name = "Test MCP"

    def check_health(self, *, profile):
        return AdapterHealth("connected", True, f"ready:{profile}")

    def capabilities(self, *, profile):
        return ["tool.discovery", f"profile:{profile}"]

    def list_tools(self, *, profile):
        return {
            "tools": [{"name": "read", "server": "test"}],
            "total": 1,
            "source": "test",
            "unavailable_servers": [],
        }


def test_framework_and_tool_adapters_have_distinct_strict_interfaces():
    assert isinstance(AresAdapter(turn_starter=lambda *_args, **_kwargs: {}), BaseLLMAdapter)
    assert isinstance(JaegerAdapter(turn_starter=lambda *_args, **_kwargs: {}), BaseLLMAdapter)
    assert isinstance(McpToolAdapter(), BaseToolAdapter)
    assert not isinstance(McpToolAdapter(), BaseLLMAdapter)


def test_registry_selects_session_runtime_without_silent_fallback(monkeypatch):
    recording = RecordingAdapter()
    registry = AdapterRegistry(execution_adapters=[recording], tool_adapters=[RecordingTools()])
    monkeypatch.setattr(
        "api.backend_selector.get_session_backend",
        lambda session, _config: session.ares_backend,
    )

    selected = registry.for_session(
        SimpleNamespace(ares_backend="recording"),
        profile="default",
    )

    assert selected is recording
    with pytest.raises(AdapterError) as exc:
        registry.execution_adapter("missing")
    assert exc.value.code == "unknown_runtime_connection"


def test_fastapi_chat_service_and_router_have_no_framework_imports():
    import fastapi_app.realtime as service_module
    import fastapi_app.routers.realtime as router_module

    source = inspect.getsource(service_module) + inspect.getsource(router_module)
    assert "api.routes" not in source
    assert "api.backends" not in source
    assert "api.jros" not in source
    assert "api.streaming" not in source


def test_framework_adapter_contains_legacy_start_seam_and_preserves_response(monkeypatch):
    captured = {}

    def starter(session_id, message, *, source):
        captured.update(session_id=session_id, message=message, source=source)
        return {"_status": 200, "stream_id": "run-1", "session_id": session_id}

    adapter = AresAdapter(turn_starter=starter)
    monkeypatch.setattr(
        adapter,
        "check_health",
        lambda **_kwargs: AdapterHealth("connected", True, "ready"),
    )
    request = ChatStart(session_id="session-1", message="Hello")

    result = asyncio.run(
        adapter.stream_chat(
            request,
            session=SimpleNamespace(session_id="session-1"),
            profile="default",
        )
    )

    assert captured == {"session_id": "session-1", "message": "Hello", "source": "webui"}
    assert result == {"stream_id": "run-1", "session_id": "session-1"}


def test_unavailable_framework_returns_bounded_error(monkeypatch):
    adapter = JaegerAdapter(turn_starter=lambda *_args, **_kwargs: pytest.fail("must not start"))
    monkeypatch.setattr(
        adapter,
        "check_health",
        lambda **_kwargs: AdapterHealth(
            "needs_attention",
            False,
            "A Companion must be configured.",
        ),
    )

    with pytest.raises(AdapterError) as exc:
        asyncio.run(
            adapter.stream_chat(
                ChatStart(session_id="session-1", message="Hello"),
                session=SimpleNamespace(session_id="session-1"),
                profile="default",
            )
        )

    assert exc.value.status_code == 400
    assert exc.value.code == "runtime_unavailable"


def test_ares_model_discovery_normalizes_existing_catalog(monkeypatch):
    monkeypatch.setattr(
        "api.config.get_available_models",
        lambda **_kwargs: {
            "groups": [
                {
                    "provider": "local",
                    "models": [{"id": "model-a", "label": "Model A"}],
                    "extra_models": ["model-b"],
                }
            ]
        },
    )

    models = AresAdapter(turn_starter=lambda *_args, **_kwargs: {}).get_models(profile="default")

    assert [model.as_dict() for model in models] == [
        {
            "id": "model-a",
            "label": "Model A",
            "provider": "local",
            "connection_id": "ares",
        },
        {
            "id": "model-b",
            "label": "model-b",
            "provider": "local",
            "connection_id": "ares",
        },
    ]


def test_mcp_adapter_is_read_only_capability_inventory(monkeypatch):
    adapter = McpToolAdapter()
    monkeypatch.setattr(
        adapter,
        "_configured_servers",
        lambda: {"notes": {"enabled": True}},
    )
    monkeypatch.setattr(
        adapter,
        "_runtime_status",
        lambda: {
            "notes": {
                "name": "notes",
                "connected": True,
                "tools": [{"name": "search_notes", "description": "Search notes"}],
            }
        },
    )

    health = adapter.check_health(profile="default")
    inventory = adapter.list_tools(profile="default")

    assert health.state == "connected"
    assert health.available is True
    assert inventory["tools"][0] == {
        "name": "search_notes",
        "server": "notes",
        "description": "Search notes",
        "active": True,
        "enabled": True,
        "status": "active",
        "schema_summary": [],
    }
    assert inventory["inventory_scope"] == "already_known_runtime_only"


def test_realtime_service_dispatches_start_and_cancel_through_selected_adapter(monkeypatch):
    recording = RecordingAdapter()
    registry = AdapterRegistry(execution_adapters=[recording], tool_adapters=[RecordingTools()])
    monkeypatch.setattr(registry, "for_session", lambda *_args, **_kwargs: recording)
    service = RealtimeService(adapter_registry=registry)
    session = SimpleNamespace(
        session_id="session-1",
        profile="default",
        read_only=False,
        workspace="/tmp",
        model=None,
        model_provider=None,
    )
    monkeypatch.setattr(service, "_session_for_profile", lambda *_args, **_kwargs: session)
    monkeypatch.setattr(service, "authorize_stream", lambda *_args, **_kwargs: "session-1")

    started = asyncio.run(
        service.start_chat(
            ChatStart(session_id="session-1", message="Hello"),
            profile="default",
        )
    )
    cancelled = service.cancel_chat("recording-run", profile="default")

    assert started == {"stream_id": "recording-run", "session_id": "session-1"}
    assert recording.started[0][2] == "default"
    assert cancelled == {"ok": True, "cancelled": True, "stream_id": "recording-run"}
    assert recording.cancelled == ["recording-run"]


def test_connection_model_and_mcp_routes_use_registry(tmp_path: Path, monkeypatch):
    recording = RecordingAdapter()
    tools = RecordingTools()
    registry = AdapterRegistry(execution_adapters=[recording], tool_adapters=[tools])
    monkeypatch.setattr(registry, "default_id", lambda **_kwargs: "recording")
    frontend = tmp_path / "dist"
    frontend.mkdir()
    (frontend / "index.html").write_text("<div id='root'></div>", encoding="utf-8")
    app = create_app(frontend_root=frontend, adapter_registry=registry)
    app.dependency_overrides[require_identity] = lambda: IDENTITY
    app.dependency_overrides[require_mutation_identity] = lambda: IDENTITY

    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        connections = client.get("/api/connections")
        models = client.get("/api/connections/recording/models")
        mcp = client.get("/api/mcp/tools")

    assert connections.status_code == 200
    assert connections.json()["selected"] == "recording"
    assert connections.json()["connections"][0]["health"]["state"] == "connected"
    assert models.json()["models"][0]["id"] == "model-1"
    assert mcp.json()["tools"][0]["name"] == "read"
