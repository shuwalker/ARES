"""ARES-owned profile creation must not depend on an external agent package."""

from __future__ import annotations

from pathlib import Path
import sys
from types import ModuleType

import pytest

from api import profiles


@pytest.fixture
def ares_home(tmp_path, monkeypatch) -> Path:
    home = tmp_path / ".ares"
    home.mkdir()
    monkeypatch.setattr(profiles, "_DEFAULT_ARES_HOME", home)
    monkeypatch.setattr(profiles, "_is_isolated_profile_mode", lambda: False)
    profiles._invalidate_list_profiles_cache()
    yield home
    profiles._invalidate_list_profiles_cache()


def test_new_profile_has_private_empty_resource_directories(ares_home):
    created = profiles.create_profile_api("testprofile")
    profile_home = ares_home / "profiles" / "testprofile"

    assert created["name"] == "testprofile"
    assert Path(created["path"]) == profile_home
    for directory in profiles._PROFILE_DIRS:
        assert (profile_home / directory).is_dir()
    assert list((profile_home / "skills").iterdir()) == []


def test_profile_creation_never_calls_external_ares_cli(ares_home, monkeypatch):
    poison = ModuleType("ares_cli.profiles")

    def forbidden(*_args, **_kwargs):
        raise AssertionError("external ares_cli profile code was called")

    poison.create_profile = forbidden
    poison.seed_profile_skills = forbidden
    package = ModuleType("ares_cli")
    package.profiles = poison
    monkeypatch.setitem(sys.modules, "ares_cli", package)
    monkeypatch.setitem(sys.modules, "ares_cli.profiles", poison)

    created = profiles.create_profile_api("internalprofile")

    assert created["name"] == "internalprofile"
    assert (ares_home / "profiles" / "internalprofile" / "skills").is_dir()


def test_clone_config_copies_only_declared_profile_config_files(ares_home):
    source = ares_home / "profiles" / "sourceprofile"
    source.mkdir(parents=True)
    (source / "config.yaml").write_text("model:\n  default: test-model\n", encoding="utf-8")
    (source / "SOUL.md").write_text("profile preferences", encoding="utf-8")
    (source / "skills").mkdir()
    (source / "skills" / "not-implicitly-cloned").mkdir()

    profiles.create_profile_api(
        "clonedprofile",
        clone_from="sourceprofile",
        clone_config=True,
    )
    destination = ares_home / "profiles" / "clonedprofile"

    assert (destination / "config.yaml").read_text(encoding="utf-8").startswith("model:")
    assert (destination / "SOUL.md").read_text(encoding="utf-8") == "profile preferences"
    assert list((destination / "skills").iterdir()) == []


def test_duplicate_profile_creation_fails_without_overwriting(ares_home):
    profiles.create_profile_api("duplicate")
    marker = ares_home / "profiles" / "duplicate" / "memory.md"
    marker.write_text("preserve", encoding="utf-8")

    with pytest.raises(FileExistsError):
        profiles.create_profile_api("duplicate")

    assert marker.read_text(encoding="utf-8") == "preserve"
