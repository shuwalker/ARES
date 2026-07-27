"""Filesystem mutation boundaries for the FastAPI skill service."""

from __future__ import annotations


def test_skill_save_and_delete_stay_inside_active_profile(tmp_path, monkeypatch):
    from api.skills_store import delete_skill, save_skill

    home = tmp_path / "profile"
    monkeypatch.setattr("api.profiles.get_active_ares_home", lambda: home)
    monkeypatch.setattr("api.profiles._SKILLS_STATS_CACHE", {})

    saved = save_skill("Code Review", "---\nname: code-review\n---\n# Review")
    skill_file = home / "skills" / "code-review" / "SKILL.md"

    assert saved["path"] == str(skill_file)
    assert skill_file.read_text(encoding="utf-8").endswith("# Review")
    assert delete_skill("code-review") == {"ok": True, "name": "code-review"}
    assert not skill_file.exists()


def test_skill_save_rejects_traversal(tmp_path, monkeypatch):
    import pytest

    from api.skills_store import SkillStoreError, save_skill

    monkeypatch.setattr("api.profiles.get_active_ares_home", lambda: tmp_path)

    with pytest.raises(SkillStoreError, match="Invalid skill name"):
        save_skill("../outside", "unsafe")
