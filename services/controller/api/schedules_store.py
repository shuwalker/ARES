"""Profile-scoped schedule storage and manual execution services."""

from __future__ import annotations

from pathlib import Path
from contextlib import closing
import datetime
import re
import sqlite3
import threading
import time
from typing import Any
import logging


_RUNNING_LOCK = threading.Lock()
_RUNNING: dict[str, float] = {}
_OUTPUT_CONTENT_LIMIT = 8_000
_OUTPUT_HEADER_CONTEXT = 200
_CRON_CREATE_SNAPSHOT_LOCK = threading.Lock()
logger = logging.getLogger(__name__)


class ScheduleStoreError(ValueError):
    def __init__(self, message: str, status_code: int = 400) -> None:
        super().__init__(message)
        self.status_code = status_code


def ensure_schedule_runtime() -> None:
    """Import the ARES-owned schedule package.

    Kept as a seam for callers that previously loaded a separate agent package.
    """
    import api.schedule_jobs  # noqa: F401


def _job_for_api(job: dict) -> dict:
    result = dict(job or {})
    result.setdefault("profile", None)
    result.setdefault("schedule_display", str(result.get("schedule") or ""))
    result["toast_notifications"] = result.get("toast_notifications") is not False
    return result


def _profile_names() -> set[str]:
    from api.profiles import list_profiles_api

    names = {"default"}
    for row in list_profiles_api():
        if isinstance(row, dict) and str(row.get("name") or "").strip():
            names.add(str(row["name"]).strip())
    return names


def _normalize_profile(value) -> str | None:
    if value is None or not str(value).strip():
        return None
    profile = str(value).strip()
    if profile not in _profile_names():
        raise ScheduleStoreError(f"Unknown profile: {profile}")
    return profile


def selected_profile_snapshot_updates(
    profile: str | None,
    *,
    provider,
    model,
) -> dict[str, str | None]:
    """Compute unpinned schedule snapshots inside the selected profile.

    Snapshot discovery consults profile-scoped environment variables.  Keep
    the environment swap and discovery under one lock without repointing the
    schedule store's module globals.
    """

    selected_profile = str(profile or "").strip()
    if not selected_profile or (provider is not None and model is not None):
        return {}
    try:
        from api.profiles import profile_env_for_background_worker
        from api.schedule_jobs import _compute_provider_model_snapshots
    except Exception:
        logger.warning(
            "Selected-profile schedule snapshot repair unavailable; saving ambient snapshots",
            exc_info=True,
        )
        return {}
    try:
        with _CRON_CREATE_SNAPSHOT_LOCK:
            with profile_env_for_background_worker(
                selected_profile,
                "cron create snapshot",
                logger_override=logger,
            ):
                provider_snapshot, model_snapshot = _compute_provider_model_snapshots(
                    provider=provider,
                    model=model,
                    base_url=None,
                    no_agent=False,
                )
    except Exception:
        logger.warning(
            "Selected-profile schedule snapshot repair failed for %s; saving ambient snapshots",
            selected_profile,
            exc_info=True,
        )
        return {}
    updates: dict[str, str | None] = {}
    if provider is None:
        updates["provider_snapshot"] = provider_snapshot
    if model is None:
        updates["model_snapshot"] = model_snapshot
    return updates


_selected_profile_snapshot_updates = selected_profile_snapshot_updates


def list_schedules(*, all_profiles: bool = False) -> dict:
    ensure_schedule_runtime()
    try:
        from api.schedule_jobs import list_jobs
    except ModuleNotFoundError as exc:
        if exc.name == "api.schedule_jobs":
            return {"jobs": [], "cron_unavailable": True}
        raise
    from api.profiles import (
        _profiles_match,
        cron_profile_context_for_home,
        get_active_profile_name,
        get_ares_home_for_profile,
        list_profiles_api,
    )

    active = get_active_profile_name() or "default"
    names = [active]
    names.extend(
        str(row.get("name") or "").strip()
        for row in list_profiles_api()
        if isinstance(row, dict) and row.get("visible") is not False
    )
    jobs = []
    foreign = []
    seen_homes = set()
    for owner in dict.fromkeys(name for name in names if name):
        home = Path(get_ares_home_for_profile(owner)).expanduser().resolve(strict=False)
        if str(home) in seen_homes:
            continue
        seen_homes.add(str(home))
        is_active = _profiles_match(owner, active)
        try:
            with cron_profile_context_for_home(home):
                rows = list_jobs(include_disabled=True)
        except Exception:
            if is_active:
                raise
            continue
        target = jobs if is_active else foreign
        target.extend(
            {
                **_job_for_api(row),
                "owner_profile": owner,
                "read_only": not is_active,
            }
            for row in rows
        )
    return {
        "jobs": jobs + foreign if all_profiles else jobs,
        "all_profiles": bool(all_profiles),
        "active_profile": active,
        "other_profile_count": 0 if all_profiles else len(foreign),
    }


def create_schedule(payload: dict[str, Any]) -> dict:
    ensure_schedule_runtime()
    from api.schedule_jobs import create_job, update_job

    profile = _normalize_profile(payload.get("profile"))
    requested_model = payload.get("model") or None
    requested_provider = payload.get("provider") or None
    try:
        job = create_job(
            prompt=payload["prompt"],
            schedule=payload["schedule"],
            name=payload.get("name") or None,
            deliver=payload.get("deliver") or "local",
            skills=payload.get("skills") or [],
            model=requested_model,
            provider=requested_provider,
        )
    except (KeyError, TypeError, ValueError) as exc:
        raise ScheduleStoreError(str(exc)) from exc
    updates = {}
    if profile is not None:
        updates["profile"] = profile
        updates.update(
            selected_profile_snapshot_updates(
                profile,
                provider=requested_provider,
                model=requested_model,
            )
        )
    if payload.get("toast_notifications") is False:
        updates["toast_notifications"] = False
    if updates:
        job = update_job(job["id"], updates) or job
    return {"ok": True, "job": _job_for_api(job)}


def update_schedule(job_id: str, updates: dict[str, Any]) -> dict:
    ensure_schedule_runtime()
    from api.schedule_jobs import update_job

    cleaned = {}
    for key, value in updates.items():
        if key == "profile":
            cleaned[key] = _normalize_profile(value)
        elif key in {"model", "provider"}:
            cleaned[key] = value or None
        elif value is not None:
            cleaned[key] = value
    job = update_job(job_id, cleaned)
    if not job:
        raise ScheduleStoreError("Job not found", 404)
    return {"ok": True, "job": _job_for_api(job)}


def delete_schedule(job_id: str) -> dict:
    ensure_schedule_runtime()
    from api.schedule_jobs import remove_job

    if not remove_job(job_id):
        raise ScheduleStoreError("Job not found", 404)
    return {"ok": True, "job_id": job_id}


def _execution_home(job: dict):
    from api.profiles import get_active_ares_home, get_ares_home_for_profile

    profile = str(job.get("profile") or "").strip()
    return get_ares_home_for_profile(profile) if profile in _profile_names() else get_active_ares_home()


def event_profile_for_schedule(job: dict) -> str | None:
    """Return the valid profile whose clients should refresh after a run."""
    profile = str((job or {}).get("profile") or "").strip()
    return profile if profile and profile in _profile_names() else None


_event_profile_for_cron_job = event_profile_for_schedule


def _mark_cron_running(job_id: str) -> None:
    with _RUNNING_LOCK:
        _RUNNING[job_id] = time.time()


def _mark_cron_done(job_id: str) -> None:
    with _RUNNING_LOCK:
        _RUNNING.pop(job_id, None)


def _is_cron_running(job_id: str) -> tuple[bool, float]:
    with _RUNNING_LOCK:
        started = _RUNNING.get(job_id)
        if started is None:
            return False, 0.0
        return True, time.time() - started


def _cron_job_subprocess_main(job, execution_profile_home, result_queue) -> None:
    try:
        def run():
            from api.schedule_scheduler import run_job

            return run_job(job)

        if execution_profile_home is None:
            result = run()
        else:
            from api.profiles import cron_profile_context_for_home

            with cron_profile_context_for_home(execution_profile_home):
                result = run()
        result_queue.put(("ok", result))
    except BaseException as exc:  # pragma: no cover - reported in parent
        import traceback

        result_queue.put(("error", f"{type(exc).__name__}: {exc}", traceback.format_exc()))


def _cron_subprocess_result_timeout_seconds(job) -> float:
    for key in ("timeout_seconds", "max_runtime_seconds", "timeout"):
        raw = (job or {}).get(key)
        if raw in (None, ""):
            continue
        try:
            value = float(raw)
        except (TypeError, ValueError):
            continue
        if value > 0:
            return max(60.0, value + 30.0)
    return 6 * 60 * 60.0


def _run_cron_job_in_profile_subprocess(
    job,
    execution_profile_home,
    *,
    process_target=None,
):
    """Run one schedule in a spawned process so profile globals stay isolated."""

    import multiprocessing
    import queue

    context = multiprocessing.get_context("spawn")
    result_queue = context.Queue(maxsize=1)
    process = context.Process(
        target=process_target or _cron_job_subprocess_main,
        args=(job, execution_profile_home, result_queue),
    )
    process.start()
    timeout = _cron_subprocess_result_timeout_seconds(job)
    status = "error"
    payload = ["schedule subprocess failed before producing a result", ""]
    try:
        try:
            status, *payload = result_queue.get(timeout=timeout)
        except queue.Empty:
            status = "error"
            if process.is_alive():
                process.terminate()
                process.join(timeout=5)
                payload = [f"schedule subprocess produced no result within {timeout:g}s and was terminated", ""]
            else:
                payload = [f"schedule subprocess exited with code {process.exitcode} without a result", ""]
        finally:
            process.join(timeout=5)
            if process.is_alive():
                process.terminate()
                process.join(timeout=5)
                if status == "ok":
                    status = "error"
                    payload = ["schedule subprocess did not exit after returning a result", ""]
    finally:
        result_queue.close()
        result_queue.join_thread()
    if status == "ok":
        return payload[0]
    if len(payload) > 1 and payload[1]:
        logger.error("Manual schedule subprocess failed:\n%s", payload[1])
    raise RuntimeError(payload[0])


def _run_cron_tracked(
    job,
    profile_home=None,
    execution_profile_home=None,
    event_profile=None,
) -> None:
    """Execute and persist a manual schedule without holding profile locks."""

    import importlib
    from api.schedule_jobs import mark_job_run, save_job_output

    scheduler = importlib.import_module("api.schedule_scheduler")
    silent_marker = getattr(scheduler, "SILENT_MARKER", "[SILENT]")
    deliver_result = getattr(scheduler, "_deliver_result", None)
    job_id = str((job or {}).get("id") or "")
    execution_profile_home = execution_profile_home or profile_home

    def with_home(home, operation):
        if home is None:
            return operation()
        from api.profiles import cron_profile_context_for_home

        with cron_profile_context_for_home(home):
            return operation()

    try:
        success, output, final_response, error = _run_cron_job_in_profile_subprocess(
            job, execution_profile_home
        )

        def persist() -> None:
            save_job_output(job_id, output)
            content = final_response if success else f"Schedule '{job.get('name', job_id)}' failed:\n{error}"
            delivery_error = None
            if content and not (success and silent_marker in content.strip().upper()) and deliver_result:
                try:
                    delivery_error = deliver_result(job, content)
                except Exception as exc:
                    delivery_error = str(exc)
                    logger.error("Delivery failed for manual schedule %s: %s", job_id, exc)
            persisted_success = bool(success and final_response)
            persisted_error = error
            if success and not final_response:
                persisted_error = "Agent completed but produced empty response (model error, timeout, or misconfiguration)"
            try:
                mark_job_run(job_id, persisted_success, persisted_error, delivery_error=delivery_error)
            except TypeError:
                mark_job_run(job_id, persisted_success, persisted_error)

        with_home(profile_home, persist)
    except Exception as exc:
        logger.exception("Manual schedule run failed for job %s", job_id)
        try:
            failure_message = str(exc)
            with_home(
                profile_home,
                lambda message=failure_message: mark_job_run(job_id, False, message),
            )
        except Exception:
            logger.debug("Failed to mark manual schedule failure for %s", job_id)
    finally:
        _mark_cron_done(job_id)
        from api.session_events import publish_session_list_changed

        publish_session_list_changed("cron_complete", profile=event_profile)


def _run_schedule_worker(job: dict, home: Path) -> None:
    _run_cron_tracked(job, home, _execution_home(job), event_profile_for_schedule(job))


def run_schedule(job_id: str) -> dict:
    ensure_schedule_runtime()
    from api.schedule_jobs import get_job

    job = get_job(job_id)
    if not job:
        raise ScheduleStoreError("Job not found", 404)
    with _RUNNING_LOCK:
        started = _RUNNING.get(job_id)
        if started is not None:
            return {
                "ok": False,
                "job_id": job_id,
                "status": "already_running",
                "elapsed": round(time.time() - started, 1),
            }
        _RUNNING[job_id] = time.time()
    threading.Thread(
        target=_run_schedule_worker,
        args=(job, _execution_home(job)),
        name=f"schedule-{job_id[:8]}",
        daemon=True,
    ).start()
    return {"ok": True, "job_id": job_id, "status": "running"}


def schedule_status(job_id: str | None = None) -> dict:
    now = time.time()
    with _RUNNING_LOCK:
        if job_id:
            started = _RUNNING.get(job_id)
            return {
                "job_id": job_id,
                "running": started is not None,
                "elapsed": round(now - started, 1) if started is not None else 0.0,
            }
        return {"running": {key: round(now - value, 1) for key, value in _RUNNING.items()}}


def pause_schedule(job_id: str, reason: str | None = None) -> dict:
    ensure_schedule_runtime()
    from api.schedule_jobs import pause_job

    result = pause_job(job_id, reason=reason)
    if not result:
        raise ScheduleStoreError("Job not found", 404)
    return {"ok": True, "job": result}


def resume_schedule(job_id: str) -> dict:
    ensure_schedule_runtime()
    from api.schedule_jobs import resume_job

    result = resume_job(job_id)
    if not result:
        raise ScheduleStoreError("Job not found", 404)
    return {"ok": True, "job": result}


def delivery_options() -> dict:
    ensure_schedule_runtime()
    try:
        from api.schedule_scheduler import _KNOWN_DELIVERY_PLATFORMS
    except Exception:
        _KNOWN_DELIVERY_PLATFORMS = frozenset()
    platforms = [
        {"value": "local", "label": "Local (save output only)"},
        {"value": "origin", "label": "Origin (reply to creator)"},
    ]
    platforms.extend(
        {"value": name, "label": name.capitalize()}
        for name in sorted(_KNOWN_DELIVERY_PLATFORMS)
    )
    return {"platforms": platforms}


def _valid_job_id(job_id: str) -> str:
    value = str(job_id or "").strip()
    if not re.fullmatch(r"[A-Za-z0-9_-][A-Za-z0-9_.-]{0,63}", value) or value in {".", ".."}:
        raise ScheduleStoreError("invalid job_id")
    return value


def _response_marker(text: str) -> int:
    positions = []
    for heading in ("## Response", "# Response"):
        if text.startswith(heading):
            positions.append(0)
        index = text.find(f"\n{heading}")
        if index >= 0:
            positions.append(index + 1)
    return min(positions) if positions else -1


def _output_window(text: str, limit: int = _OUTPUT_CONTENT_LIMIT) -> str:
    if len(text) <= limit:
        return text
    marker = _response_marker(text)
    if marker >= 0:
        header = text[: min(_OUTPUT_HEADER_CONTEXT, marker)].rstrip()
        response = text[marker:].lstrip("\n")
        return (f"{header}\n...\n{response}" if header else response)[:limit]
    return text[-limit:]


def _output_snippet(text: str, limit: int = 600) -> str:
    lines = text.split("\n")
    marker = next(
        (index for index, line in enumerate(lines) if line.startswith(("## Response", "# Response"))),
        -1,
    )
    body = "\n".join(lines[marker + 1 :] if marker >= 0 else lines).strip()
    return body[:limit] or "(empty)"


def _output_usage(text: str) -> dict:
    head = text.split("## Response", 1)[0].split("# Response", 1)[0]
    usage = {}

    def integer(value):
        cleaned = re.sub(r"[^0-9]", "", value or "")
        return int(cleaned) if cleaned else None

    def floating(value):
        match = re.search(r"[-+]?\d+(?:\.\d+)?", (value or "").replace(",", ""))
        return float(match.group(0)) if match else None

    for line in (row.strip() for row in head.splitlines()):
        match = re.match(r"\*\*(?:Model|Model Used):\*\*\s*(.+)$", line, re.I)
        if match:
            usage["model"] = match.group(1).strip()
            continue
        match = re.match(r"\*\*Provider:\*\*\s*(.+)$", line, re.I)
        if match:
            usage["provider"] = match.group(1).strip()
            continue
        match = re.match(r"\*\*(?:Estimated cost|Cost):\*\*\s*(.+)$", line, re.I)
        if match and (value := floating(match.group(1))) is not None:
            usage["estimated_cost_usd"] = value
            continue
        match = re.match(r"\*\*(?:Duration|Elapsed):\*\*\s*(.+)$", line, re.I)
        if match and (value := floating(match.group(1))) is not None:
            usage["duration_seconds"] = value
            continue
        match = re.match(r"\*\*Tokens:\*\*\s*(.+)$", line, re.I)
        if not match:
            continue
        value = match.group(1)
        for key, pattern in (
            ("input_tokens", r"([0-9][0-9,]*)\s*(?:input|in)\b"),
            ("output_tokens", r"([0-9][0-9,]*)\s*(?:output|out)\b"),
            ("total_tokens", r"([0-9][0-9,]*)\s*(?:total\s*)?tokens?\b"),
        ):
            found = re.search(pattern, value, re.I)
            if found:
                usage[key] = integer(found.group(1))
    if "total_tokens" not in usage:
        total = int(usage.get("input_tokens") or 0) + int(usage.get("output_tokens") or 0)
        if total:
            usage["total_tokens"] = total
    return usage


def schedule_outputs(job_id: str, limit: Any = 5) -> dict:
    ensure_schedule_runtime()
    from api.schedule_jobs import OUTPUT_DIR

    job_id = _valid_job_id(job_id)
    try:
        parsed_limit = max(1, min(500, int(limit)))
    except (TypeError, ValueError):
        parsed_limit = 5
    output_dir = OUTPUT_DIR / job_id
    outputs = []
    if output_dir.exists():
        files = sorted(
            output_dir.glob("*.md"),
            key=lambda path: path.stat().st_mtime,
            reverse=True,
        )[:parsed_limit]
        for path in files:
            try:
                content = path.read_text(encoding="utf-8", errors="replace")
                outputs.append({"filename": path.name, "content": _output_window(content)})
            except OSError:
                continue
    return {"job_id": job_id, "outputs": outputs}


def schedule_history(job_id: str, offset: Any = 0, limit: Any = 50) -> dict:
    ensure_schedule_runtime()
    from api.schedule_jobs import OUTPUT_DIR

    job_id = _valid_job_id(job_id)
    try:
        parsed_offset = max(0, int(offset))
        parsed_limit = max(1, min(500, int(limit)))
    except (TypeError, ValueError) as exc:
        raise ScheduleStoreError("offset and limit must be integers") from exc
    output_dir = OUTPUT_DIR / job_id
    runs = []
    files = []
    if output_dir.exists():
        files = sorted(output_dir.glob("*.md"), key=lambda path: path.stat().st_mtime, reverse=True)
        for path in files[parsed_offset : parsed_offset + parsed_limit]:
            try:
                stat = path.stat()
                content = path.read_text(encoding="utf-8", errors="replace")
                runs.append(
                    {
                        "filename": path.name,
                        "size": stat.st_size,
                        "modified": stat.st_mtime,
                        "usage": _output_usage(content),
                    }
                )
            except OSError:
                continue
    return {"job_id": job_id, "runs": runs, "total": len(files), "offset": parsed_offset}


def schedule_run_detail(job_id: str, filename: str) -> dict:
    ensure_schedule_runtime()
    from api.schedule_jobs import OUTPUT_DIR

    job_id = _valid_job_id(job_id)
    output_root = OUTPUT_DIR.resolve()
    path = (OUTPUT_DIR / job_id / str(filename or "")).resolve()
    if not path.is_relative_to(output_root):
        raise ScheduleStoreError("invalid filename")
    if not path.is_file():
        raise ScheduleStoreError("run not found", 404)
    try:
        content = path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        raise ScheduleStoreError(str(exc), 500) from exc
    return {
        "job_id": job_id,
        "filename": filename,
        "content": content,
        "snippet": _output_snippet(content),
        "usage": _output_usage(content),
    }


def _latest_sessions(job_ids: list[str]) -> dict[str, dict]:
    from api.models import _active_state_db_path

    results = {job_id: {"session_id": "", "message_count": None} for job_id in job_ids}
    path = _active_state_db_path()
    if not path or not Path(path).exists() or not job_ids:
        return results
    try:
        with closing(sqlite3.connect(str(path))) as connection:
            connection.row_factory = sqlite3.Row
            columns = {
                row[1]
                for row in connection.execute("PRAGMA table_info(sessions)").fetchall()
            }
            if not {"id", "source"}.issubset(columns):
                return results
            count_select = "message_count" if "message_count" in columns else "NULL AS message_count"
            order = "COALESCE(started_at, 0) DESC, id DESC" if "started_at" in columns else "id DESC"
            rows = connection.execute(
                f"SELECT id, {count_select} FROM sessions "
                f"WHERE LOWER(COALESCE(source, '')) = 'cron' ORDER BY {order}"
            ).fetchall()
            for row in rows:
                session_id = str(row["id"] or "")
                matches = [job_id for job_id in job_ids if session_id.startswith(f"cron_{job_id}_")]
                if not matches:
                    continue
                job_id = max(matches, key=len)
                if results[job_id]["session_id"]:
                    continue
                results[job_id] = {
                    "session_id": session_id,
                    "message_count": int(row["message_count"]) if row["message_count"] is not None else None,
                }
    except sqlite3.Error:
        pass
    return results


def recent_schedules(since: Any = 0) -> dict:
    ensure_schedule_runtime()
    try:
        parsed_since = float(since)
    except (TypeError, ValueError):
        parsed_since = 0.0
    try:
        from api.schedule_jobs import list_jobs
    except ImportError:
        return {"completions": [], "since": parsed_since}
    jobs = list_jobs(include_disabled=True)
    completions = []
    for job in jobs:
        last_run = job.get("last_run_at")
        if not last_run:
            continue
        try:
            completed_at = (
                datetime.datetime.fromisoformat(last_run.replace("Z", "+00:00")).timestamp()
                if isinstance(last_run, str)
                else float(last_run)
            )
        except (TypeError, ValueError):
            continue
        if completed_at <= parsed_since:
            continue
        completions.append(
            {
                "job_id": str(job.get("id") or ""),
                "name": job.get("name", "Unknown"),
                "status": job.get("last_status", "unknown"),
                "completed_at": completed_at,
                "toast_notifications": job.get("toast_notifications") is not False,
            }
        )
    session_info = _latest_sessions([row["job_id"] for row in completions])
    for completion in completions:
        info = session_info.get(completion["job_id"], {})
        completion["session_id"] = str(info.get("session_id") or "")
        if info.get("message_count") is not None:
            completion["message_count"] = int(info["message_count"])
    return {"completions": completions, "since": parsed_since}
