"""Regenerate-title materializes CLI/TUI sessions through the shared boundary."""

from __future__ import annotations

import pytest


def test_regenerate_uses_materialization_boundary(monkeypatch):
    from api.session_mutations import regenerate_session_title

    calls = []
    session = type("Session", (), {"session_id": "cli-session"})()
    monkeypatch.setattr(
        "api.session_access.get_or_materialize_session",
        lambda session_id: calls.append(session_id) or session,
    )
    monkeypatch.setattr(
        "api.streaming.generate_session_title_for_session",
        lambda value, prefer_latest=False: ("Generated", "ok", "raw"),
    )
    monkeypatch.setattr(
        "api.session_mutations.persist_generated_session_title",
        lambda value, title, event_reason: value,
    )

    updated, reason, preview = regenerate_session_title("cli-session")

    assert updated is session
    assert calls == ["cli-session"]
    assert (reason, preview) == ("ok", "raw")


def test_regenerate_propagates_read_only_materialization_error(monkeypatch):
    from api.session_mutations import regenerate_session_title

    def reject(_session_id):
        raise PermissionError("read-only imported session")

    monkeypatch.setattr("api.session_access.get_or_materialize_session", reject)

    with pytest.raises(PermissionError, match="read-only"):
        regenerate_session_title("imported-session")
