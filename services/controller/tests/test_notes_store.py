"""Notes source gating and Joplin translation contracts."""

from __future__ import annotations


def test_notes_sources_are_disabled_by_default(monkeypatch):
    from api.notes_store import list_sources

    monkeypatch.delenv("ARES_WEBUI_EXTERNAL_NOTES_SOURCES", raising=False)
    monkeypatch.setattr("api.config.get_config", lambda: {})

    result = list_sources()

    assert result["enabled"] is False
    assert result["sources"] == []
    assert result["attach_supported"] is False


def test_joplin_search_translates_and_bounds_results(monkeypatch):
    from api.notes_store import search_notes

    monkeypatch.setenv("ARES_WEBUI_EXTERNAL_NOTES_SOURCES", "1")
    monkeypatch.setattr(
        "api.notes_store._joplin_get",
        lambda path, params: {
            "items": [
                {
                    "id": "a" * 32,
                    "title": "Architecture",
                    "body": "A  local\nprofile note",
                    "parent_id": "b" * 32,
                    "updated_time": 123,
                }
            ]
        },
    )

    result = search_notes("profile", limit=500)

    assert result["query"] == "profile"
    assert result["results"][0]["snippet"] == "A local profile note"
