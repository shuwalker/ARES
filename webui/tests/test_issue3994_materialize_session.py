"""Regression tests for #3994 / #3985 — _get_or_materialize_session().

rename / move / update of a CLI/agent session that isn't yet in the WebUI store
should materialize it from CLI metadata (mirroring /api/session/archive) instead
of 404ing — while still refusing to mutate a read-only (messaging / Claude Code)
session.
"""
from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import patch

import pytest


def test_materialize_returns_in_store_session_directly():
    """When get_session() succeeds, the helper returns it (after full-load) untouched."""
    import api.session_access as routes

    existing = SimpleNamespace(session_id="s1", profile="default", messages=[])
    with patch("api.models.get_session", return_value=existing), \
         patch("api.session_access.ensure_full_session_before_mutation", return_value=existing):
        out = routes._get_or_materialize_session("s1")
    assert out is existing


def test_materialize_missing_everywhere_raises_keyerror():
    """No WebUI session and no CLI metadata → KeyError (caller maps to 404)."""
    import api.session_access as routes

    with patch("api.models.get_session", side_effect=KeyError("s1")), \
         patch("api.session_access.lookup_cli_session_metadata", return_value={}):
        with pytest.raises(KeyError):
            routes._get_or_materialize_session("s1")


def test_materialize_readonly_session_raises_permissionerror():
    """A read-only imported session (messaging / Claude Code) must not be materialized
    for mutation — the helper raises PermissionError (caller maps to 403)."""
    import api.session_access as routes

    with patch("api.models.get_session", side_effect=KeyError("ro1")), \
         patch("api.session_access.lookup_cli_session_metadata", return_value={"read_only": True, "source_tag": "claude_code"}):
        with pytest.raises(PermissionError):
            routes._get_or_materialize_session("ro1")


def test_materialize_cli_session_imports_full_history():
    """A regular (non-messaging, non-read-only) CLI session is materialized via
    import_cli_session with its message history."""
    import api.session_access as routes

    cli_meta = {
        "read_only": False,
        "title": "CLI chat",
        "model": "gpt-test",
        "profile": "default",
        "source_tag": "cli",
    }
    imported = SimpleNamespace(session_id="cli1", profile="default", messages=[{"role": "user", "content": "hi"}])
    with patch("api.models.get_session", side_effect=KeyError("cli1")), \
         patch("api.session_access.lookup_cli_session_metadata", return_value=cli_meta), \
         patch("api.session_access.is_messaging_session_record", return_value=False), \
         patch("api.models.get_cli_session_messages", return_value=[{"role": "user", "content": "hi"}]), \
         patch("api.models.title_from", return_value="CLI chat"), \
         patch("api.models.import_cli_session", return_value=imported) as mock_import:
        out = routes._get_or_materialize_session("cli1")
    assert out is imported
    assert mock_import.called
    # source metadata is stamped onto the materialized session
    assert getattr(out, "is_cli_session", None) is True


def test_materialize_rejects_stored_readonly_session():
    """An already-STORED read-only session must be refused on the happy path too —
    get_session() succeeding doesn't make it mutable (Codex CORE #1)."""
    import api.session_access as routes

    ro = SimpleNamespace(session_id="ro_stored", profile="default", messages=[], read_only=True)
    with patch("api.models.get_session", return_value=ro), \
         patch("api.session_access.ensure_full_session_before_mutation", return_value=ro):
        with pytest.raises(PermissionError):
            routes._get_or_materialize_session("ro_stored")


def test_materialize_allows_stored_messaging_session_without_readonly():
    """A stored messaging session that ALREADY owns its sidecar is mutable on the
    happy path (the messaging-fork concern only applies to the materialize
    fallback that would CREATE a sidecar). Only an explicit read_only flag blocks
    a stored session."""
    import api.session_access as routes

    msg = SimpleNamespace(session_id="msg_stored", profile="default", messages=[],
                          session_source="messaging", source_tag="telegram", read_only=False)
    with patch("api.models.get_session", return_value=msg), \
         patch("api.session_access.ensure_full_session_before_mutation", return_value=msg):
        out = routes._get_or_materialize_session("msg_stored")
    assert out is msg


def test_materialize_rejects_messaging_cli_meta_without_readonly_flag():
    """Messaging cli_meta lacking an explicit read_only flag must still be refused
    — agent rows normalize messaging sources without setting read_only, and
    state.db is the source of truth, so a writable sidecar would fork it (Codex CORE #2)."""
    import api.session_access as routes

    cli_meta = {"title": "tg chat", "model": "gpt-test", "source_tag": "telegram", "session_source": "messaging"}
    with patch("api.models.get_session", side_effect=KeyError("msg1")), \
         patch("api.session_access.lookup_cli_session_metadata", return_value=cli_meta), \
         patch("api.models.import_cli_session") as mock_import:
        with pytest.raises(PermissionError):
            routes._get_or_materialize_session("msg1")
    assert not mock_import.called, "must not import a messaging session"
