"""Native WebUI zero-message orphan reconciliation contracts."""

from __future__ import annotations

from types import SimpleNamespace

from api.session_listing import prune_orphaned_webui_zero_message_sessions


def _install_model_fakes(monkeypatch, *, empty=(), sidecars=None, tombstones=()):
    import api.models

    calls = {"pruned": [], "recorded": [], "cleared": []}
    empty = set(empty)
    sidecars = dict(sidecars or {})
    monkeypatch.setattr(
        api.models,
        "agent_session_zero_message_sids",
        lambda ids, **_kwargs: set(ids) & empty,
    )
    monkeypatch.setattr(api.models, "_load_webui_zero_message_orphan_tombstone", lambda: frozenset(tombstones))
    monkeypatch.setattr(api.models, "prune_session_from_index", calls["pruned"].append)
    monkeypatch.setattr(api.models, "_record_webui_zero_message_orphan_tombstone", calls["recorded"].append)
    monkeypatch.setattr(api.models, "_clear_webui_zero_message_orphan_tombstone", calls["cleared"].append)
    monkeypatch.setattr(
        api.models.Session,
        "load",
        staticmethod(lambda sid: SimpleNamespace(messages=sidecars.get(sid, []))),
    )
    return calls


def test_confirmed_empty_titled_webui_row_is_pruned_and_tombstoned(monkeypatch):
    calls = _install_model_fakes(monkeypatch, empty={"empty"})
    row = {"session_id": "empty", "source": "webui", "title": "Started", "message_count": 4}
    assert prune_orphaned_webui_zero_message_sessions([row]) == []
    assert calls["pruned"] == ["empty"]
    assert calls["recorded"] == ["empty"]


def test_active_pending_and_worktree_rows_are_never_probed(monkeypatch):
    import api.models

    monkeypatch.setattr(
        api.models,
        "agent_session_zero_message_sids",
        lambda *_a, **_k: (_ for _ in ()).throw(AssertionError("unexpected probe")),
    )
    rows = [
        {"session_id": "active", "source": "webui", "title": "A", "active_stream_id": "run"},
        {"session_id": "pending", "source": "webui", "title": "B", "has_pending_user_message": True},
        {"session_id": "tree", "source": "webui", "title": "C", "worktree_path": "/tmp/tree"},
    ]
    assert prune_orphaned_webui_zero_message_sessions(rows) == rows


def test_sidecar_messages_retain_row_while_state_database_catches_up(monkeypatch):
    calls = _install_model_fakes(
        monkeypatch,
        empty={"sidecar-only"},
        sidecars={"sidecar-only": [{"role": "user", "content": "hello"}]},
        tombstones={"sidecar-only"},
    )
    row = {"session_id": "sidecar-only", "source": "webui", "title": "Conversation"}
    assert prune_orphaned_webui_zero_message_sessions([row]) == [row]
    assert calls["cleared"] == ["sidecar-only"]
    assert calls["pruned"] == []


def test_existing_state_messages_self_heal_an_old_tombstone(monkeypatch):
    calls = _install_model_fakes(monkeypatch, empty=set(), tombstones={"recovered"})
    row = {"session_id": "recovered", "source": "webui", "title": "Conversation"}
    assert prune_orphaned_webui_zero_message_sessions([row]) == [row]
    assert calls["cleared"] == ["recovered"]


def test_untitled_zero_count_draft_is_left_to_model_visibility_policy(monkeypatch):
    import api.models

    monkeypatch.setattr(
        api.models,
        "agent_session_zero_message_sids",
        lambda *_a, **_k: (_ for _ in ()).throw(AssertionError("unexpected probe")),
    )
    row = {"session_id": "draft", "source": "webui", "title": "Untitled", "message_count": 0}
    assert prune_orphaned_webui_zero_message_sessions([row]) == [row]
