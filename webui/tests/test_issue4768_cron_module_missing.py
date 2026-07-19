"""ARES schedule storage is an internal production dependency."""

from __future__ import annotations

def test_list_schedules_uses_internal_schedule_module(monkeypatch, tmp_path):
    import api.schedule_jobs as jobs
    from api.profiles import cron_profile_context_for_home
    from api.schedules_store import list_schedules

    monkeypatch.setattr("api.profiles.get_active_profile_name", lambda: "default")
    monkeypatch.setattr("api.profiles.get_ares_home_for_profile", lambda _profile: tmp_path)
    monkeypatch.setattr("api.profiles.list_profiles_api", lambda: [])
    with cron_profile_context_for_home(tmp_path):
        jobs.create_job(prompt="internal", schedule="0 9 * * *")
    result = list_schedules()

    assert result["jobs"][0]["prompt"] == "internal"
    assert "cron_unavailable" not in result
