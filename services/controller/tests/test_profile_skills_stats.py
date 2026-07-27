import sys
from pathlib import Path
import yaml
from api import profiles


def _write_skill(root: Path, name: str, platforms=None):
    skill_dir = root / "skills" / name
    skill_dir.mkdir(parents=True, exist_ok=True)
    platforms_line = f"platforms: {platforms}\n" if platforms else ""
    (skill_dir / "SKILL.md").write_text(
        f"---\nname: {name}\ndescription: {name} skill\n{platforms_line}---\n\n# {name}\n",
        encoding="utf-8",
    )

def _write_config(home: Path, disabled):
    home.mkdir(parents=True, exist_ok=True)
    (home / "config.yaml").write_text(
        yaml.safe_dump({"skills": {"disabled": list(disabled)}}, sort_keys=False),
        encoding="utf-8",
    )

def test_get_profile_skills_stats(tmp_path):
    # Setup skills directory with:
    # 1 compatible & enabled skill ("alpha")
    # 1 compatible & disabled skill ("beta")
    # 1 incompatible skill ("gamma" is explicitly tagged for another OS)
    profile_home = tmp_path / "auditor"
    _write_skill(profile_home, "alpha")
    _write_skill(profile_home, "beta")
    incompatible_platform = "linux" if sys.platform == "darwin" else "macos"
    _write_skill(profile_home, "gamma", platforms=[incompatible_platform])
    _write_config(profile_home, ["beta"])

    # Explicitly clear the stats cache to ensure we compute fresh
    profiles._SKILLS_STATS_CACHE.clear()

    enabled, compatible = profiles._get_profile_skills_stats(profile_home)
    assert enabled == 1
    assert compatible == 2

def test_list_profiles_api_contains_formatted_skills(monkeypatch, tmp_path):
    """ARES-owned profile discovery formats skill counts for each profile."""
    p_default = tmp_path / "default"
    profiles_root = p_default / "profiles"
    p_fintech = profiles_root / "fintech"

    _write_skill(p_default, "a1")
    _write_skill(p_default, "a2")
    _write_config(p_default, ["a2"])

    _write_skill(p_fintech, "f1")
    _write_skill(p_fintech, "f2")
    _write_skill(p_fintech, "f3")
    _write_config(p_fintech, ["f2", "f3"])

    monkeypatch.setattr(profiles, "get_active_profile_name", lambda: "default")

    monkeypatch.setattr(profiles, "_DEFAULT_ARES_HOME", p_default)

    profiles._SKILLS_STATS_CACHE.clear()
    profiles._invalidate_list_profiles_cache()

    results = profiles.list_profiles_api()
    by_name = {p["name"]: p for p in results}

    assert "default" in by_name
    assert "fintech" in by_name

    # backward-compatible skill_count as an integer:
    assert by_name["default"]["skill_count"] == 1
    assert by_name["fintech"]["skill_count"] == 1

    # new enabled_skills and total_skills integer fields:
    assert by_name["default"]["enabled_skills"] == 1
    assert by_name["default"]["total_skills"] == 2
    assert by_name["fintech"]["enabled_skills"] == 1
    assert by_name["fintech"]["total_skills"] == 3

    # the base home is surfaced as the default profile
    assert by_name["default"]["is_default"] is True
    assert by_name["fintech"]["is_default"] is False
    # exactly one active, and it's the one get_active_profile_name reports
    assert sum(1 for p in results if p["is_active"]) == 1
    assert by_name["default"]["is_active"] is True

    profiles._invalidate_list_profiles_cache()

def test_no_skills_dir(tmp_path):
    """Profile with no skills/ directory should return (0, 0)."""
    profiles._SKILLS_STATS_CACHE.clear()
    enabled, compat = profiles._get_profile_skills_stats(tmp_path)
    assert enabled == 0 and compat == 0

def test_corrupt_config(tmp_path):
    """Corrupt config.yaml should not crash — disabled set stays empty."""
    profiles._SKILLS_STATS_CACHE.clear()
    _write_skill(tmp_path, "a")
    (tmp_path / "config.yaml").write_text("not: [valid: yaml: {{", encoding="utf-8")
    enabled, compat = profiles._get_profile_skills_stats(tmp_path)
    assert compat == 1 and enabled == 1  # no disabled parsing, all enabled

def test_platform_disabled_webui(tmp_path):
    """platform_disabled.webui list should be used when present."""
    profiles._SKILLS_STATS_CACHE.clear()
    _write_skill(tmp_path, "web-only")
    cfg = {"skills": {"platform_disabled": {"webui": ["web-only"]}, "disabled": []}}
    (tmp_path / "config.yaml").write_text(yaml.safe_dump(cfg), encoding="utf-8")
    enabled, compat = profiles._get_profile_skills_stats(tmp_path)
    assert compat == 1 and enabled == 0

def test_skills_stats_cache(tmp_path):
    """Caching avoids re-parsing SKILL.md, but the per-call mtime probe catches
    a real skill add/remove immediately (the #4783 fix — adding a skill bumps
    the skills-dir mtime, so the next call recomputes rather than serving stale
    counts for the whole TTL)."""
    profiles._SKILLS_STATS_CACHE.clear()

    _write_skill(tmp_path, "alpha")
    enabled, compat = profiles._get_profile_skills_stats(tmp_path)
    assert enabled == 1 and compat == 1

    # A second call with NO change serves the cache (no recompute) — same value.
    enabled, compat = profiles._get_profile_skills_stats(tmp_path)
    assert enabled == 1 and compat == 1

    # Adding a skill bumps the skills-dir mtime; the cheap probe detects it on
    # the very next call and the counts update immediately (no stale TTL window).
    _write_skill(tmp_path, "beta")
    # Guarantee the skills-dir mtime is STRICTLY newer than the cached probe value.
    # A real FS-backed skill-add always advances the dir mtime, but two writes inside
    # the same coarse mtime tick can leave it byte-identical under full-suite timing —
    # the source of this test's intermittent flake (order-dependent: passes in
    # isolation, fails ~intermittently under full-suite ordering). Forcing it forward
    # keeps the assertion honest (the probe must recompute on a genuine mtime change)
    # without racing the filesystem's mtime granularity.
    import os as _os, time as _time
    _skills_dir = tmp_path / "skills"
    _future = _time.time() + 5
    _os.utime(_skills_dir, (_future, _future))
    enabled, compat = profiles._get_profile_skills_stats(tmp_path)
    assert enabled == 2 and compat == 2

    # .clear() still forces a fresh recompute regardless of mtime/TTL.
    profiles._SKILLS_STATS_CACHE.clear()
    enabled, compat = profiles._get_profile_skills_stats(tmp_path)
    assert enabled == 2 and compat == 2


def test_list_profiles_api_ignores_invalid_profile_directories(monkeypatch, tmp_path):
    """Filesystem discovery accepts only valid ARES profile identifiers."""
    p_default = tmp_path / "default"
    _write_skill(p_default, "a1")
    _write_config(p_default, [])
    (p_default / "profiles" / "valid-profile").mkdir(parents=True)
    (p_default / "profiles" / ".invalid").mkdir()

    monkeypatch.setattr(profiles, "_DEFAULT_ARES_HOME", p_default)
    monkeypatch.setattr(profiles, "get_active_profile_name", lambda: "default")

    profiles._SKILLS_STATS_CACHE.clear()
    profiles._invalidate_list_profiles_cache()

    results = profiles.list_profiles_api()
    assert {p["name"] for p in results} == {"default", "valid-profile"}

    profiles._invalidate_list_profiles_cache()


def test_list_profiles_api_caches_and_invalidates(monkeypatch, tmp_path):
    """Repeated calls hit the TTL cache; create/delete invalidation drops it."""
    p_default = tmp_path / "default"
    _write_skill(p_default, "a1")
    _write_config(p_default, [])

    monkeypatch.setattr(profiles, "_DEFAULT_ARES_HOME", p_default)
    monkeypatch.setattr(profiles, "get_active_profile_name", lambda: "default")

    build_calls = []
    real_build = profiles._build_profile_rows_fast

    def counting_build():
        build_calls.append(1)
        return real_build()

    monkeypatch.setattr(profiles, "_build_profile_rows_fast", counting_build)

    profiles._SKILLS_STATS_CACHE.clear()
    profiles._invalidate_list_profiles_cache()

    profiles.list_profiles_api()
    profiles.list_profiles_api()
    # Second call should be served from the TTL cache — no rebuild.
    assert len(build_calls) == 1, "second call within TTL must hit the cache"

    # Invalidation forces a rebuild on the next call.
    profiles._invalidate_list_profiles_cache()
    profiles.list_profiles_api()
    assert len(build_calls) == 2, "invalidation must force a rebuild"

    profiles._invalidate_list_profiles_cache()


def test_list_profiles_api_reads_model_metadata_without_external_cli(monkeypatch, tmp_path):
    p_default = tmp_path / "default"
    _write_skill(p_default, "a1")
    _write_config(p_default, [])
    config = yaml.safe_load((p_default / "config.yaml").read_text(encoding="utf-8"))
    config["model"] = {"default": "gpt-test", "provider": "external-test"}
    (p_default / "config.yaml").write_text(yaml.safe_dump(config), encoding="utf-8")

    monkeypatch.setattr(profiles, "_DEFAULT_ARES_HOME", p_default)
    monkeypatch.setattr(profiles, "get_active_profile_name", lambda: "default")

    profiles._SKILLS_STATS_CACHE.clear()
    profiles._invalidate_list_profiles_cache()

    results = profiles.list_profiles_api()
    by_name = {p["name"]: p for p in results}
    assert by_name["default"]["model"] == "gpt-test"
    assert by_name["default"]["provider"] == "external-test"

    profiles._invalidate_list_profiles_cache()
