"""Legacy todo-state projection remains confined to runtime compatibility."""

from __future__ import annotations

import inspect


def test_stream_completion_projection_uses_canonical_todo_state_helper():
    from api.streaming import _session_payload_with_full_messages

    source = inspect.getsource(_session_payload_with_full_messages)
    assert "attach_todo_state(raw, messages)" in source


def test_fastapi_session_service_does_not_own_legacy_todo_state():
    import fastapi_app.services as services

    source = inspect.getsource(services)
    assert "attach_todo_state" not in source
