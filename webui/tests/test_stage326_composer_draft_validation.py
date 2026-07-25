"""Composer-draft input and persistence hardening."""

from contextlib import nullcontext
from types import SimpleNamespace

from api.session_mutations import MAX_DRAFT_FILES, MAX_DRAFT_TEXT, save_session_draft


def _session(monkeypatch, draft=None):
    calls = []
    session = SimpleNamespace(composer_draft=draft or {})

    def save(**kwargs):
        calls.append(kwargs)

    session.save = save
    monkeypatch.setattr("api.models.get_session", lambda _session_id: session)
    monkeypatch.setattr("api.config._get_session_agent_lock", lambda _session_id: nullcontext())
    return session, calls


def test_draft_text_clamped_to_50kb(monkeypatch):
    session, _calls = _session(monkeypatch)
    save_session_draft("session", text="x" * (MAX_DRAFT_TEXT + 10))
    assert len(session.composer_draft["text"]) == 50_000


def test_draft_files_clamped_to_50_entries(monkeypatch):
    session, _calls = _session(monkeypatch)
    save_session_draft("session", files=list(range(MAX_DRAFT_FILES + 10)))
    assert session.composer_draft["files"] == list(range(50))


def test_draft_text_type_coerced_to_empty_string(monkeypatch):
    session, _calls = _session(monkeypatch)
    save_session_draft("session", text={"not": "text"})
    assert session.composer_draft["text"] == ""


def test_draft_files_type_coerced_to_list(monkeypatch):
    session, _calls = _session(monkeypatch)
    save_session_draft("session", files="not-a-list")
    assert session.composer_draft["files"] == []


def test_draft_save_preserves_updated_at_and_skips_index(monkeypatch):
    _session_value, calls = _session(monkeypatch)
    save_session_draft("session", text="new")
    assert calls == [{"touch_updated_at": False, "skip_index": True}]


def test_unchanged_draft_does_not_persist(monkeypatch):
    _session_value, calls = _session(monkeypatch, {"text": "same"})
    result = save_session_draft("session", text="same")
    assert result["unchanged"] is True
    assert calls == []
