"""Archived scheduled/webhook conversations retain sidecar ownership."""

from __future__ import annotations

from types import SimpleNamespace

from api.agent_sessions import is_cli_session_row
from api.session_access import is_claimable_cli_source


def test_cron_rows_are_not_cli_even_with_stale_cli_flag():
    row = {
        "session_id": "cron_job123_20260618",
        "source_tag": "cron",
        "raw_source": "cron",
        "session_source": "cron",
        "is_cli_session": True,
    }
    assert is_cli_session_row(row) is False


def test_cron_and_webhook_sources_are_not_claimable_runtime_sessions():
    assert is_claimable_cli_source({"source_tag": "cron"})[0] is False
    # Webhooks are server-owned projections.  Marking them read-only is the
    # explicit local-profile contract used by the projected sidebar row.
    assert is_claimable_cli_source({"source_tag": "webhook", "read_only": True})[0] is False


def test_archived_sidecar_wins_over_fresh_state_projection(monkeypatch):
    """The FastAPI session service must not let a raw projection unarchive a row."""

    import api.config
    import api.models
    import api.profiles
    import api.session_runtime_state
    from fastapi_app.services import AresCoreService

    sidecar = {
        "session_id": "cron_job123_20260618",
        "title": "Cron Session",
        "source_tag": "cron",
        "profile": "default",
        "archived": True,
        "updated_at": 10,
    }
    projection = dict(sidecar, archived=False, updated_at=20)
    monkeypatch.setattr(api.models, "all_sessions", lambda: [dict(sidecar)])
    monkeypatch.setattr(api.models, "get_cli_sessions", lambda **_kwargs: [dict(projection)])
    monkeypatch.setattr(api.config, "load_settings", lambda: {"show_cli_sessions": True})
    monkeypatch.setattr(api.profiles, "get_active_profile_name", lambda: "default")
    monkeypatch.setattr(api.profiles, "_profiles_match", lambda left, right: (left or "default") == right)
    monkeypatch.setattr(
        api.session_runtime_state,
        "reconcile_stale_stream_state_for_session_rows",
        lambda _rows: False,
    )

    payload = AresCoreService().sessions(
        profile="default",
        exclude_hidden=False,
        include_archived=True,
    )
    assert payload["sessions"] == [sidecar]
    assert payload["archived_count"] == 1


def test_default_sidebar_hides_archived_sidecar(monkeypatch):
    import api.config
    import api.models
    import api.profiles
    import api.session_runtime_state
    from fastapi_app.services import AresCoreService

    sidecar = {
        "session_id": "webhook_archive_20260618",
        "source_tag": "webhook",
        "profile": "default",
        "archived": True,
        "updated_at": 10,
    }
    monkeypatch.setattr(api.models, "all_sessions", lambda: [dict(sidecar)])
    monkeypatch.setattr(api.models, "get_cli_sessions", lambda **_kwargs: [])
    monkeypatch.setattr(api.config, "load_settings", lambda: {"show_cli_sessions": False})
    monkeypatch.setattr(api.profiles, "get_active_profile_name", lambda: "default")
    monkeypatch.setattr(api.profiles, "_profiles_match", lambda left, right: (left or "default") == right)
    monkeypatch.setattr(api.session_runtime_state, "reconcile_stale_stream_state_for_session_rows", lambda _rows: False)

    payload = AresCoreService().sessions(
        profile="default",
        exclude_hidden=False,
        include_archived=False,
    )
    assert payload["sessions"] == []
    assert payload["archived_count"] == 1
