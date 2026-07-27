"""Profile-scoped durable schedule storage owned by ARES."""

from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import tempfile
import threading
from typing import Any
import uuid


ARES_DIR = Path(os.environ.get("ARES_HOME", "~/.ares")).expanduser()
CRON_DIR = ARES_DIR / "cron"
JOBS_FILE = CRON_DIR / "jobs.json"
OUTPUT_DIR = CRON_DIR / "output"
_LOCK = threading.RLock()


def _ensure_storage() -> None:
    CRON_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
    try:
        CRON_DIR.chmod(0o700)
        OUTPUT_DIR.chmod(0o700)
    except OSError:
        pass


def _read_jobs() -> list[dict[str, Any]]:
    _ensure_storage()
    if not JOBS_FILE.is_file():
        return []
    try:
        payload = json.loads(JOBS_FILE.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return []
    rows = payload.get("jobs", []) if isinstance(payload, dict) else payload
    return [dict(row) for row in rows if isinstance(row, dict)] if isinstance(rows, list) else []


def _write_jobs(jobs: list[dict[str, Any]]) -> None:
    _ensure_storage()
    fd, temporary = tempfile.mkstemp(prefix="jobs-", suffix=".json", dir=CRON_DIR)
    path = Path(temporary)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump({"jobs": jobs}, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        path.chmod(0o600)
        os.replace(path, JOBS_FILE)
        JOBS_FILE.chmod(0o600)
    finally:
        if path.exists():
            path.unlink(missing_ok=True)


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def list_jobs(include_disabled: bool = False) -> list[dict[str, Any]]:
    with _LOCK:
        jobs = _read_jobs()
    if include_disabled:
        return jobs
    return [job for job in jobs if job.get("enabled", True) and not job.get("paused", False)]


def get_job(job_id: str) -> dict[str, Any] | None:
    return next((job for job in list_jobs(include_disabled=True) if job.get("id") == job_id), None)


def create_job(**values) -> dict[str, Any]:
    prompt = str(values.get("prompt") or "").strip()
    schedule = str(values.get("schedule") or "").strip()
    if not prompt or not schedule:
        raise ValueError("prompt and schedule are required")
    now = _now()
    job = {
        "id": uuid.uuid4().hex[:16],
        "name": str(values.get("name") or prompt[:80]).strip(),
        "prompt": prompt,
        "schedule": schedule,
        "deliver": str(values.get("deliver") or "local").strip().lower(),
        "skills": [str(item) for item in values.get("skills") or []],
        "model": values.get("model") or None,
        "provider": values.get("provider") or None,
        "enabled": True,
        "paused": False,
        "created_at": now,
        "updated_at": now,
    }
    with _LOCK:
        jobs = _read_jobs()
        jobs.append(job)
        _write_jobs(jobs)
    return dict(job)


def update_job(job_id: str, updates: dict[str, Any]) -> dict[str, Any] | None:
    with _LOCK:
        jobs = _read_jobs()
        for index, job in enumerate(jobs):
            if job.get("id") != job_id:
                continue
            safe_updates = {key: value for key, value in dict(updates or {}).items() if key != "id"}
            jobs[index] = {**job, **safe_updates, "updated_at": _now()}
            _write_jobs(jobs)
            return dict(jobs[index])
    return None


def remove_job(job_id: str) -> bool:
    with _LOCK:
        jobs = _read_jobs()
        retained = [job for job in jobs if job.get("id") != job_id]
        if len(retained) == len(jobs):
            return False
        _write_jobs(retained)
    return True


def pause_job(job_id: str, reason: str | None = None) -> dict[str, Any] | None:
    return update_job(job_id, {"paused": True, "pause_reason": reason or None})


def resume_job(job_id: str) -> dict[str, Any] | None:
    return update_job(job_id, {"paused": False, "pause_reason": None})


def mark_job_run(job_id: str, success: bool, error: str | None = None) -> dict[str, Any] | None:
    return update_job(
        job_id,
        {
            "last_run_at": _now(),
            "last_status": "success" if success else "failed",
            "last_error": error or None,
        },
    )


def save_job_output(job_id: str, output: str) -> Path:
    safe_id = str(job_id).replace("/", "_").replace("\\", "_")
    destination = OUTPUT_DIR / safe_id
    destination.mkdir(parents=True, exist_ok=True, mode=0o700)
    filename = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ.md")
    path = destination / filename
    path.write_text(str(output or ""), encoding="utf-8")
    try:
        destination.chmod(0o700)
        path.chmod(0o600)
    except OSError:
        pass
    return path


def _compute_provider_model_snapshots(**_kwargs) -> tuple[None, None]:
    """Unpinned jobs resolve the elected runtime/model when they execute."""
    return None, None
