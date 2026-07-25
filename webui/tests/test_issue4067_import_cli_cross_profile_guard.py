"""Cross-profile isolation for transport-neutral CLI session imports (#4067)."""

from __future__ import annotations

import pytest

import api.cli_session_import as cli_import


class FakeSession:
    def __init__(self, session_id, profile):
        self.session_id = session_id
        self.profile = profile
        self.messages = [{"role": "user", "content": "FOREIGN_SECRET"}]
        self.source_tag = "cli"
        self.raw_source = "cli"
        self.session_source = "cli"
        self.source_label = "CLI"
        self.parent_session_id = None
        self.read_only = False

    def compact(self):
        return {"id": self.session_id, "profile": self.profile}

    def save(self, touch_updated_at=False):
        raise AssertionError("must not save/refresh a foreign-profile session")


def test_existing_foreign_profile_unqualified_request_is_404(monkeypatch):
    foreign = FakeSession("foreign_existing_001", "other")
    monkeypatch.setattr(cli_import.Session, "load", staticmethod(lambda _sid: foreign))
    monkeypatch.setattr(
        cli_import,
        "get_cli_session_messages",
        lambda *_args, **_kwargs: pytest.fail("foreign read attempted"),
    )
    with pytest.raises(cli_import.CliImportError) as raised:
        cli_import.import_cli_session_record(
            "foreign_existing_001",
            active_profile="default",
        )
    assert raised.value.status_code == 404


def test_existing_same_profile_still_refreshes(monkeypatch):
    own = FakeSession("own_001", "default")
    own.save = lambda touch_updated_at=False: None
    monkeypatch.setattr(cli_import.Session, "load", staticmethod(lambda _sid: own))
    monkeypatch.setattr(cli_import, "_lookup_metadata", lambda *_args, **_kwargs: {})
    monkeypatch.setattr(cli_import, "get_cli_session_messages", lambda *_args, **_kwargs: [])
    response = cli_import.import_cli_session_record("own_001", active_profile="default")
    assert response["session"]["id"] == "own_001"
    assert response["imported"] is False


def test_all_profiles_requires_matching_requested_profile(monkeypatch):
    foreign = FakeSession("foreign_002", "other")
    monkeypatch.setattr(cli_import.Session, "load", staticmethod(lambda _sid: foreign))
    monkeypatch.setattr(cli_import, "_is_isolated_profile_mode", lambda: False)
    monkeypatch.setattr(
        cli_import,
        "get_cli_session_messages",
        lambda *_args, **_kwargs: pytest.fail("foreign read attempted"),
    )
    with pytest.raises(cli_import.CliImportError) as raised:
        cli_import.import_cli_session_record(
            "foreign_002",
            all_profiles=True,
            requested_profile="haku",
            active_profile="default",
        )
    assert raised.value.status_code == 404
