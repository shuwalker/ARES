import os

import pytest

from api import skills_store


def test_skill_save_rejects_symlinked_skill_file(tmp_path, monkeypatch):
    skills_dir = tmp_path / "skills"
    skill_dir = skills_dir / "demo"
    skill_dir.mkdir(parents=True)
    outside = tmp_path / "outside.md"
    outside.write_text("important", encoding="utf-8")
    link = skill_dir / "SKILL.md"
    try:
        os.symlink(str(outside), str(link))
    except (OSError, NotImplementedError):
        pytest.skip("platform does not support symlinks")

    monkeypatch.setattr(skills_store, "active_skills_dir", lambda: skills_dir)

    with pytest.raises(
        skills_store.SkillStoreError,
        match="Cannot save to a symlinked skill file",
    ):
        skills_store.save_skill("demo", "changed")
    assert outside.read_text(encoding="utf-8") == "important"


def test_skill_save_real_file_still_works(tmp_path, monkeypatch):
    skills_dir = tmp_path / "skills"

    monkeypatch.setattr(skills_store, "active_skills_dir", lambda: skills_dir)
    result = skills_store.save_skill("Demo Skill", "# Demo\n")

    skill_file = skills_dir / "demo-skill" / "SKILL.md"
    assert result["ok"] is True
    assert skill_file.read_text(encoding="utf-8") == "# Demo\n"
