"""The FastAPI adapter is the sole transport-to-runtime chat seam."""

from __future__ import annotations

import asyncio
import types

from fastapi_app.adapters.base import AdapterHealth
from fastapi_app.adapters.frameworks import JournaledFrameworkAdapter
from fastapi_app.schemas import ChatStart


class _Backend:
    def capabilities(self):
        return {"chat": True}


class _AvailableAdapter(JournaledFrameworkAdapter):
    adapter_id = "test"
    display_name = "Test runtime"

    def check_health(self, *, profile):
        return AdapterHealth("connected", True, "ready")


def test_framework_adapter_calls_the_transport_neutral_turn_starter():
    captured = {}

    def start(session_id, message, *, source):
        captured.update(session_id=session_id, message=message, source=source)
        return {"stream_id": "stream-1", "session_id": session_id}

    adapter = _AvailableAdapter(backend=_Backend(), turn_starter=start)
    request = ChatStart(session_id="session-1", message="wake up")
    session = types.SimpleNamespace(session_id="session-1")

    result = asyncio.run(adapter.stream_chat(request, session=session, profile="default"))

    assert result["stream_id"] == "stream-1"
    assert captured == {
        "session_id": "session-1",
        "message": "wake up",
        "source": "webui",
    }


def test_adapter_no_longer_imports_the_deleted_http_dispatcher():
    import inspect
    import fastapi_app.adapters.frameworks as frameworks

    assert "api.routes" not in inspect.getsource(frameworks)
