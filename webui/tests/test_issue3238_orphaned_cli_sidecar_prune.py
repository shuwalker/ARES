"""Imported session sidecars remain projections, not independent records."""

from __future__ import annotations

from api.session_listing import prune_orphaned_agent_sidecars, session_source_is_webui


def test_native_webui_session_with_cli_ancestor_is_never_pruned(monkeypatch):
    import api.models

    pruned = []
    monkeypatch.setattr(api.models, "agent_session_rows_existing", lambda *_a, **_k: set())
    monkeypatch.setattr(api.models, "prune_session_from_index", pruned.append)
    row = {
        "session_id": "webui-child",
        "source": "webui",
        "source_session_id": "cli-parent",
        "is_cli_session": True,
    }
    assert prune_orphaned_agent_sidecars([row], []) == [row]
    assert pruned == []


def test_orphaned_imported_cli_and_api_sidecars_are_pruned(monkeypatch):
    import api.models

    pruned = []
    monkeypatch.setattr(api.models, "agent_session_rows_existing", lambda *_a, **_k: set())
    monkeypatch.setattr(api.models, "prune_session_from_index", pruned.append)
    rows = [
        {"session_id": "cli-orphan", "source": "cli", "is_cli_session": True},
        {"session_id": "api-orphan", "source_tag": "api_server"},
    ]
    assert prune_orphaned_agent_sidecars(rows, []) == []
    assert set(pruned) == {"cli-orphan", "api-orphan"}


def test_state_backed_imported_sidecar_is_retained_when_outside_visible_window(monkeypatch):
    import api.models

    monkeypatch.setattr(
        api.models,
        "agent_session_rows_existing",
        lambda ids, **_kwargs: {"older-cli"} & set(ids),
    )
    monkeypatch.setattr(
        api.models,
        "prune_session_from_index",
        lambda _sid: (_ for _ in ()).throw(AssertionError("must not prune")),
    )
    row = {"session_id": "older-cli", "source": "cli", "is_cli_session": True}
    assert prune_orphaned_agent_sidecars([row], []) == [row]


def test_current_cli_catalog_row_does_not_require_state_probe(monkeypatch):
    import api.models

    monkeypatch.setattr(
        api.models,
        "agent_session_rows_existing",
        lambda *_a, **_k: (_ for _ in ()).throw(AssertionError("unexpected probe")),
    )
    row = {"session_id": "visible-cli", "source": "cli", "is_cli_session": True}
    assert prune_orphaned_agent_sidecars([row], [{"session_id": "visible-cli"}]) == [row]


def test_webui_source_detection_uses_explicit_source_fields_only():
    assert session_source_is_webui({"source": "webui"})
    assert session_source_is_webui({"session_source": "web-ui"})
    assert not session_source_is_webui({"source": "cli", "source_session_id": "webui-parent"})
