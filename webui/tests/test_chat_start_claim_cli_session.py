"""Foreign-session claiming contracts on the FastAPI chat boundary."""

from __future__ import annotations

from pathlib import Path

from fastapi.testclient import TestClient

from api.models import Session
from api.session_access import (
    claim_or_synthesize_cli_session,
    is_claimable_cli_source,
)
from fastapi_app.main import create_app
from fastapi_app.realtime import RealtimeService
from fastapi_app.request_context import (
    RequestIdentity,
    require_identity,
    require_mutation_identity,
)


class _Adapter:
    def __init__(self):
        self.calls = []

    async def stream_chat(self, request, *, session, profile):
        self.calls.append((request.message, session.session_id, profile))
        return {"ok": True, "stream_id": "claim-stream", "session_id": session.session_id}


class _Registry:
    def __init__(self, adapter):
        self.adapter = adapter

    def for_session(self, _session, *, profile=None):
        return self.adapter


def _client(tmp_path: Path, adapter: _Adapter) -> TestClient:
    app = create_app(
        frontend_root=tmp_path / "missing-dist",
        realtime_service=RealtimeService(adapter_registry=_Registry(adapter)),
    )
    identity = RequestIdentity(session_cookie=None, profile="default", auth_enabled=False)
    app.dependency_overrides[require_identity] = lambda: identity
    app.dependency_overrides[require_mutation_identity] = lambda: identity
    return TestClient(app)


def test_claim_classifier_keeps_local_cli_and_tui_writable():
    assert is_claimable_cli_source({"source_tag": "cli"}) == (True, "")
    assert is_claimable_cli_source({}, "tui") == (True, "")


def test_claim_classifier_refuses_foreign_owned_sources():
    for source in ("cron", "gateway", "claude_code", "messaging", "external_agent", "subagent", "unknown"):
        claimable, reason = is_claimable_cli_source({"source_tag": source})
        assert claimable is False
        assert source in reason
    assert is_claimable_cli_source({"read_only": True}) == (False, "explicit_readonly")


def test_claim_helper_rejects_unsafe_and_missing_sessions(monkeypatch):
    session, reason = claim_or_synthesize_cli_session("../unsafe")
    assert session is None
    assert reason == "invalid_sid"

    monkeypatch.setattr("api.session_access.state_db_session_source", lambda _sid: "")
    monkeypatch.setattr("api.session_access.lookup_cli_session_metadata", lambda _sid: {})
    monkeypatch.setattr("api.models.get_cli_session_messages", lambda _sid: [])
    session, reason = claim_or_synthesize_cli_session("missing_foreign_session")
    assert session is None
    assert reason == "no_foreign_state"


def test_claim_helper_preserves_metadata_and_marks_cron_read_only(monkeypatch, tmp_path):
    metadata = {"source_tag": "cron", "title": "Scheduled run", "workspace": str(tmp_path)}
    original = dict(metadata)
    monkeypatch.setattr("api.session_access.state_db_session_source", lambda _sid: "cron")
    monkeypatch.setattr("api.session_access.session_index_marks_was_webui", lambda _sid: False)
    monkeypatch.setattr("api.models._load_webui_deleted_session_tombstone", lambda: frozenset())
    monkeypatch.setattr(
        "api.models.get_cli_session_messages",
        lambda _sid: [{"role": "user", "content": "run"}],
    )

    session, reason = claim_or_synthesize_cli_session("cron_session", cli_meta=metadata)

    assert reason == "not_claimable"
    assert session.read_only is True
    assert session.source_tag == "cron"
    assert metadata == original


def test_chat_start_returns_403_for_foreign_owned_session(monkeypatch, tmp_path):
    session = Session(
        session_id="readonly_cron",
        profile="default",
        workspace=str(tmp_path),
        model="test-model",
        messages=[{"role": "user", "content": "scheduled"}],
        source_tag="cron",
        read_only=True,
    )
    adapter = _Adapter()
    monkeypatch.setattr("api.models.get_session", lambda *_args, **_kwargs: (_ for _ in ()).throw(KeyError()))
    monkeypatch.setattr(
        "api.session_access.claim_or_synthesize_cli_session",
        lambda _sid: (session, "not_claimable"),
    )

    response = _client(tmp_path, adapter).post(
        "/api/chat/start",
        json={"session_id": session.session_id, "message": "continue"},
    )

    assert response.status_code == 403
    assert adapter.calls == []


def test_chat_start_claims_local_cli_session_and_uses_adapter(monkeypatch, tmp_path):
    session = Session(
        session_id="claimable_tui",
        profile="default",
        workspace=str(tmp_path),
        model="test-model",
        messages=[{"role": "assistant", "content": "prior answer"}],
        source_tag="tui",
        is_cli_session=True,
    )
    adapter = _Adapter()
    monkeypatch.setattr("api.models.get_session", lambda *_args, **_kwargs: (_ for _ in ()).throw(KeyError()))
    monkeypatch.setattr(
        "api.session_access.claim_or_synthesize_cli_session",
        lambda _sid: (session, "materialized"),
    )
    monkeypatch.setattr(session, "save", lambda *args, **kwargs: None)

    response = _client(tmp_path, adapter).post(
        "/api/chat/start",
        json={"session_id": session.session_id, "message": "continue"},
    )

    assert response.status_code == 200
    assert adapter.calls == [("continue", session.session_id, "default")]
