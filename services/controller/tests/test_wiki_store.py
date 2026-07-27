"""Wiki allowlist and page-read security contracts."""

from __future__ import annotations


def test_wiki_browse_and_read_only_expose_allowlisted_markdown(tmp_path, monkeypatch):
    from api.wiki_store import browse, read_page

    root = tmp_path / "wiki"
    concepts = root / "concepts"
    concepts.mkdir(parents=True)
    page = concepts / "profiles.md"
    page.write_text("# Local Profiles", encoding="utf-8")
    (root / ".env").write_text("SECRET=hidden", encoding="utf-8")
    monkeypatch.setattr("api.wiki_store.resolve_root", lambda: (root, "test", True))

    listed = browse()

    assert [row["path"] for row in listed["pages"]] == ["concepts/profiles.md"]
    assert read_page("concepts/profiles.md") == {
        "content": "# Local Profiles",
        "path": "concepts/profiles.md",
    }


def test_wiki_rejects_traversal_and_symlink_pages(tmp_path, monkeypatch):
    import pytest

    from api.wiki_store import WikiStoreError, browse, read_page

    root = tmp_path / "wiki"
    concepts = root / "concepts"
    concepts.mkdir(parents=True)
    outside = tmp_path / "secret.md"
    outside.write_text("secret", encoding="utf-8")
    (concepts / "linked.md").symlink_to(outside)
    monkeypatch.setattr("api.wiki_store.resolve_root", lambda: (root, "test", True))

    assert browse()["pages"] == []
    with pytest.raises(WikiStoreError, match="Invalid path"):
        read_page("../secret.md")
    with pytest.raises(WikiStoreError, match="Page not found"):
        read_page("concepts/linked.md")
