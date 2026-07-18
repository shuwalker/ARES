"""Schedule query validation without the legacy HTTP handler namespace."""

from __future__ import annotations

import os
import sys
import types


def _stub_cron_jobs(monkeypatch, *, output_dir=None, jobs=None):
    cron_package = types.ModuleType("cron")
    cron_package.__path__ = []
    cron_jobs = types.ModuleType("cron.jobs")
    if output_dir is not None:
        cron_jobs.OUTPUT_DIR = output_dir
    if jobs is not None:
        cron_jobs.list_jobs = lambda include_disabled=True: jobs
    monkeypatch.setitem(sys.modules, "cron", cron_package)
    monkeypatch.setitem(sys.modules, "cron.jobs", cron_jobs)
    monkeypatch.setattr("api.schedules_store.ensure_schedule_runtime", lambda: None)


def test_cron_output_non_numeric_limit_does_not_500(monkeypatch, tmp_path):
    from api.schedules_store import schedule_outputs

    _stub_cron_jobs(monkeypatch, output_dir=tmp_path / "cron-out")

    assert schedule_outputs("abc123", "notanint") == {
        "job_id": "abc123",
        "outputs": [],
    }


def test_cron_output_negative_limit_is_clamped(monkeypatch, tmp_path):
    from api.schedules_store import schedule_outputs

    output_dir = tmp_path / "cron-out" / "job42"
    output_dir.mkdir(parents=True)
    for index in range(3):
        path = output_dir / f"run-{index}.md"
        path.write_text(f"## Response\noutput {index}\n", encoding="utf-8")
        os.utime(path, (1000 + index, 1000 + index))
    _stub_cron_jobs(monkeypatch, output_dir=tmp_path / "cron-out")

    result = schedule_outputs("job42", -3)

    assert result["outputs"][0]["filename"] == "run-2.md"


def test_cron_output_valid_limit_still_works(monkeypatch, tmp_path):
    from api.schedules_store import schedule_outputs

    _stub_cron_jobs(monkeypatch, output_dir=tmp_path / "cron-out")
    assert schedule_outputs("nonexistent", 20)["outputs"] == []


def test_cron_recent_non_numeric_since_does_not_500(monkeypatch):
    from api.schedules_store import recent_schedules

    _stub_cron_jobs(
        monkeypatch,
        jobs=[{"id": "a", "name": "Job A", "last_run_at": 50, "last_status": "success"}],
    )
    monkeypatch.setattr("api.schedules_store._latest_sessions", lambda ids: {})

    result = recent_schedules("notanum")

    assert result["since"] == 0.0
    assert {item["job_id"] for item in result["completions"]} == {"a"}


def test_cron_recent_valid_since_still_filters(monkeypatch):
    from api.schedules_store import recent_schedules

    _stub_cron_jobs(
        monkeypatch,
        jobs=[
            {"id": "old", "name": "Old", "last_run_at": 5, "last_status": "success"},
            {"id": "new", "name": "New", "last_run_at": 50, "last_status": "success"},
        ],
    )
    monkeypatch.setattr("api.schedules_store._latest_sessions", lambda ids: {})

    result = recent_schedules(10)

    assert result["since"] == 10.0
    assert {item["job_id"] for item in result["completions"]} == {"new"}
