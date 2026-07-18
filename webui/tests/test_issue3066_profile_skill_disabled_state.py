from pathlib import Path

import yaml

from tests.conftest import requires_agent_modules


def _write_skill(root: Path, name: str):
    skill_dir = root / "skills" / name
    skill_dir.mkdir(parents=True, exist_ok=True)
    (skill_dir / "SKILL.md").write_text(
        f"---\nname: {name}\ndescription: {name} skill\n---\n\n# {name}\n",
        encoding="utf-8",
    )


def _write_config(home: Path, disabled):
    home.mkdir(parents=True, exist_ok=True)
    (home / "config.yaml").write_text(
        yaml.safe_dump({"skills": {"disabled": list(disabled)}}, sort_keys=False),
        encoding="utf-8",
    )


def _load_config(home: Path):
    return yaml.safe_load((home / "config.yaml").read_text(encoding="utf-8")) or {}


@requires_agent_modules
def test_skills_list_reads_disabled_state_from_active_profile(monkeypatch, tmp_path):
    """#3066: the skill directory and disabled toggle state must use the same profile."""
    from api import profiles, skills_store

    default_home = tmp_path / "default"
    active_home = tmp_path / "profiles" / "auditor"
    for name in ("alpha", "beta"):
        _write_skill(active_home, name)
    _write_config(default_home, ["alpha"])
    _write_config(active_home, ["beta"])

    monkeypatch.setenv("ARES_HOME", str(default_home))
    monkeypatch.setattr(profiles, "get_active_ares_home", lambda: active_home)

    listed = skills_store.list_skills()["skills"]
    by_name = {skill["name"]: skill for skill in listed}

    assert by_name["alpha"]["disabled"] is False
    assert by_name["beta"]["disabled"] is True


@requires_agent_modules
def test_skill_toggle_writes_active_profile_config_not_default(monkeypatch, tmp_path):
    """#3066: WebUI toggle writes the active profile config, not default ARES_HOME."""
    from api import config, profiles, skills_store

    default_home = tmp_path / "default"
    active_home = tmp_path / "profiles" / "trader"
    _write_skill(active_home, "gamma")
    _write_config(default_home, [])
    _write_config(active_home, ["gamma"])

    monkeypatch.setenv("ARES_HOME", str(default_home))
    monkeypatch.setattr(profiles, "get_active_ares_home", lambda: active_home)
    monkeypatch.setattr(config, "reload_config", lambda: None)

    enabled_response = skills_store.toggle_skill("gamma", True)
    assert enabled_response == {"ok": True, "name": "gamma", "enabled": True}
    assert _load_config(active_home)["skills"]["disabled"] == []
    assert _load_config(default_home)["skills"]["disabled"] == []

    disabled_response = skills_store.toggle_skill("gamma", False)
    assert disabled_response == {"ok": True, "name": "gamma", "enabled": False}
    assert _load_config(active_home)["skills"]["disabled"] == ["gamma"]
    assert _load_config(default_home)["skills"]["disabled"] == []
