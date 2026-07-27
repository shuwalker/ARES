"""Cron-origin sessions are materialized before a FastAPI chat run."""

from __future__ import annotations

from types import SimpleNamespace

import pytest

from fastapi_app.realtime import RealtimeService
from fastapi_app.schemas import ChatStart


@pytest.mark.asyncio
async def test_chat_start_materializes_cron_session_before_reply(monkeypatch, tmp_path):
    session_id = "cron_job123_20260615_101544"
    session = SimpleNamespace(
        session_id=session_id,
        workspace=str(tmp_path),
        model="gpt-5.4",
        model_provider=None,
        profile="default",
        read_only=False,
    )
    captured = {}

    monkeypatch.setattr("api.models.get_session", lambda _sid: (_ for _ in ()).throw(KeyError(_sid)))
    monkeypatch.setattr(
        "api.session_access.get_or_materialize_session",
        lambda sid: captured.setdefault("materialized", sid) and session,
    )
    monkeypatch.setattr("api.profiles.get_active_profile_name", lambda: "default")

    class Adapter:
        async def stream_chat(self, request, *, session, profile):
            captured.update(request=request, session=session, profile=profile)
            return {"stream_id": "stream-3975", "session_id": session.session_id}

    class Registry:
        def for_session(self, selected, *, profile):
            assert selected is session
            return Adapter()

    result = await RealtimeService(adapter_registry=Registry()).start_chat(
        ChatStart(session_id=session_id, message="follow up", profile="default"),
        profile="default",
    )
    assert result["stream_id"] == "stream-3975"
    assert captured["materialized"] == session_id
    assert captured["session"] is session
