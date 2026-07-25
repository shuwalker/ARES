"""Schedule service translation and duplicate-run state contracts."""

from __future__ import annotations

import sys
import types


def test_schedule_create_preserves_optional_profile_and_notification_fields(monkeypatch):
    from api.schedules_store import create_schedule

    jobs = types.ModuleType("api.schedule_jobs")
    jobs.create_job = lambda **values: {"id": "job-1", **values}
    jobs.update_job = lambda job_id, values: {"id": job_id, **values}
    cron = types.ModuleType("cron")
    cron.__path__ = []
    monkeypatch.setitem(sys.modules, "cron", cron)
    monkeypatch.setitem(sys.modules, "api.schedule_jobs", jobs)
    monkeypatch.setattr("api.schedules_store.ensure_schedule_runtime", lambda: None)
    monkeypatch.setattr(
        "api.profiles.list_profiles_api",
        lambda: [{"name": "default"}, {"name": "work"}],
    )

    result = create_schedule(
        {
            "prompt": "Review tasks",
            "schedule": "0 9 * * *",
            "profile": "work",
            "toast_notifications": False,
        }
    )

    assert result["ok"] is True
    assert result["job"]["profile"] == "work"
    assert result["job"]["toast_notifications"] is False


def test_schedule_status_is_idle_without_a_worker():
    from api.schedules_store import schedule_status

    assert schedule_status("not-running") == {
        "job_id": "not-running",
        "running": False,
        "elapsed": 0.0,
    }
