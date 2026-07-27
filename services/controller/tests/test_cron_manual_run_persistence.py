"""Manual schedule execution is owned by the schedule service."""

from __future__ import annotations

from contextlib import nullcontext
from pathlib import Path
import sys
import types

import api.schedules_store as schedules


def _runtime(monkeypatch, job, calls):
    jobs = types.ModuleType("api.schedule_jobs")
    jobs.get_job = lambda job_id: job if job_id == job["id"] else None
    jobs.mark_job_run = lambda *_args, **_kwargs: None
    jobs.save_job_output = lambda *_args, **_kwargs: None
    scheduler = types.ModuleType("api.schedule_scheduler")
    scheduler.run_job = lambda value: calls.append(("run", value["id"]))
    monkeypatch.setitem(sys.modules, "api.schedule_jobs", jobs)
    monkeypatch.setitem(sys.modules, "api.schedule_scheduler", scheduler)
    monkeypatch.setattr(schedules, "ensure_schedule_runtime", lambda: None)
    monkeypatch.setattr(
        schedules,
        "_run_cron_job_in_profile_subprocess",
        lambda value, _home: (
            sys.modules["api.schedule_scheduler"].run_job(value) or (True, "", "ok", "")
        ),
    )
    monkeypatch.setattr(schedules, "_execution_home", lambda _job: Path("/tmp/ares-test"))
    monkeypatch.setattr(
        "api.profiles.cron_profile_context_for_home",
        lambda _home: nullcontext(),
    )


def test_manual_schedule_run_registers_worker(monkeypatch):
    calls = []
    job = {"id": "job123"}
    _runtime(monkeypatch, job, calls)

    class ImmediateThread:
        def __init__(self, target, args, **_kwargs):
            self.target, self.args = target, args

        def start(self):
            self.target(*self.args)

    monkeypatch.setattr(schedules.threading, "Thread", ImmediateThread)
    result = schedules.run_schedule("job123")
    assert result == {"ok": True, "job_id": "job123", "status": "running"}
    assert calls == [("run", "job123")]
    assert schedules.schedule_status("job123")["running"] is False


def test_manual_schedule_duplicate_is_bounded(monkeypatch):
    calls = []
    job = {"id": "job-busy"}
    _runtime(monkeypatch, job, calls)
    with schedules._RUNNING_LOCK:
        schedules._RUNNING["job-busy"] = schedules.time.time()
    try:
        result = schedules.run_schedule("job-busy")
        assert result["ok"] is False
        assert result["status"] == "already_running"
        assert calls == []
    finally:
        with schedules._RUNNING_LOCK:
            schedules._RUNNING.pop("job-busy", None)


def test_worker_failure_releases_running_marker(monkeypatch):
    calls = []
    job = {"id": "job-failed"}
    _runtime(monkeypatch, job, calls)
    sys.modules["api.schedule_scheduler"].run_job = lambda _job: (_ for _ in ()).throw(RuntimeError("boom"))
    with schedules._RUNNING_LOCK:
        schedules._RUNNING[job["id"]] = schedules.time.time()
    try:
        try:
            schedules._run_schedule_worker(job, Path("/tmp/ares-test"))
        except RuntimeError:
            pass
        assert schedules.schedule_status(job["id"])["running"] is False
    finally:
        with schedules._RUNNING_LOCK:
            schedules._RUNNING.pop(job["id"], None)
