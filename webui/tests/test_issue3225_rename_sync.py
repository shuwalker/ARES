"""Session rename writes through to state.db before notifying subscribers."""

from __future__ import annotations

from contextlib import nullcontext


def test_rename_syncs_title_before_session_list_event(monkeypatch):
    from api.session_mutations import rename_session

    events: list[str] = []

    class Session:
        session_id = "rename-sync"
        title = "Old"
        profile = "default"
        read_only = False
        _loaded_metadata_only = False

        def save(self):
            events.append("save")

    session = Session()
    monkeypatch.setattr("api.models.get_session", lambda _sid: session)
    monkeypatch.setattr("api.config._get_session_agent_lock", lambda _sid: nullcontext())
    monkeypatch.setattr(
        "api.session_mutations._sync_session_title_to_insights",
        lambda _session: events.append("sync"),
    )
    monkeypatch.setattr(
        "api.session_events.publish_session_list_changed",
        lambda *_args, **_kwargs: events.append("publish"),
    )

    result = rename_session("rename-sync", "New title")

    assert result.title == "New title"
    assert events == ["save", "sync", "publish"]
