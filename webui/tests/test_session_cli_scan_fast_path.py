"""Session projection avoids unnecessary CLI scans while preserving external metadata."""

from api.models import Session
import api.session_projection as projection


def test_webui_session_metadata_load_skips_cli_metadata_scan(monkeypatch):
    session = Session(
        session_id="webui_normal",
        title="Normal WebUI chat",
        messages=[{"role": "user", "content": "hello"}],
    )
    monkeypatch.setattr(
        projection,
        "lookup_cli_session_metadata",
        lambda _sid: (_ for _ in ()).throw(AssertionError("normal WebUI loads should not scan CLI sessions")),
    )

    response = projection.project_session_detail(session, load_messages=False, resolve_model=False)
    assert response["session_id"] == "webui_normal"
    assert response["messages"] == []


def test_read_only_session_metadata_load_preserves_cli_metadata_lookup(monkeypatch):
    session = Session(
        session_id="readonly_sidecar",
        title="Imported chat",
        messages=[{"role": "user", "content": "hello"}],
        read_only=True,
    )
    looked_up = []

    def lookup(session_id):
        looked_up.append(session_id)
        return {"session_id": session_id, "read_only": True, "source_label": "External Agent"}

    monkeypatch.setattr(projection, "lookup_cli_session_metadata", lookup)
    response = projection.project_session_detail(session, load_messages=False, resolve_model=False)
    assert looked_up == ["readonly_sidecar"]
    assert response["read_only"] is True


def test_messaging_session_metadata_load_preserves_cli_metadata_lookup(monkeypatch):
    session = Session(
        session_id="messaging_sidecar",
        title="Telegram chat",
        messages=[{"role": "user", "content": "hello"}],
        session_source="messaging",
        raw_source="telegram",
    )
    looked_up = []

    def lookup(session_id):
        looked_up.append(session_id)
        return {
            "session_id": session_id,
            "session_source": "messaging",
            "raw_source": "telegram",
            "source_label": "Telegram",
        }

    monkeypatch.setattr(projection, "lookup_cli_session_metadata", lookup)
    monkeypatch.setattr("api.models.get_cli_session_messages", lambda _sid, profile=None: [])
    response = projection.project_session_detail(session, load_messages=False, resolve_model=False)
    assert looked_up == ["messaging_sidecar"]
    assert response["source_label"] == "Telegram"


def test_messaging_session_metadata_matches_full_display_merge(monkeypatch):
    sidecar = [
        {"role": "user", "content": "hi", "timestamp": 1000},
        {"role": "assistant", "content": "ok", "timestamp": 1001},
    ]
    external = sidecar + [{"role": "assistant", "content": "ok", "timestamp": 1001.7}]
    session = Session(
        session_id="telegram_resume",
        title="Telegram",
        messages=sidecar,
        session_source="messaging",
        raw_source="telegram",
    )
    monkeypatch.setattr(
        projection,
        "lookup_cli_session_metadata",
        lambda sid: {"session_id": sid, "session_source": "messaging", "raw_source": "telegram"},
    )
    monkeypatch.setattr("api.models.get_cli_session_messages", lambda _sid, profile=None: external)
    full = projection.project_session_detail(session, load_messages=True, resolve_model=False)
    metadata = projection.project_session_detail(session, load_messages=False, resolve_model=False)
    assert (metadata["message_count"], metadata["last_message_at"]) == (
        full["message_count"], full["last_message_at"]
    )
