"""Pending-approval store for ARES checkpoints.

One JSON file per task at ~/.ares/approvals/<task_id>.json. The daemon
writes a record when the executor hits a stage with requires_approval=True,
then polls for a status change. The IPC server (and `ares approve` /
`ares reject`) updates the record.
"""

from __future__ import annotations

import json
import os
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any

from ..config import ares_paths


def _dir() -> Path:
    return ares_paths()["approvals"]


def _path(task_id: str) -> Path:
    return _dir() / f"{task_id}.json"


def _atomic_write(path: Path, data: dict[str, Any]) -> None:
    # Write to a tmpfile in the same dir, then os.replace for atomicity —
    # otherwise an IPC reader could see a half-written JSON document.
    fd, tmp = tempfile.mkstemp(prefix=path.name + ".", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w") as fh:
            json.dump(data, fh)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except FileNotFoundError:
            pass
        raise


def create_pending(
    task_id: str,
    stage_id: int,
    stage_name: str,
    message: str,
    timeout_s: int,
) -> dict[str, Any]:
    now = datetime.now(timezone.utc)
    record = {
        "task_id": task_id,
        "stage_id": stage_id,
        "stage_name": stage_name,
        "message": message,
        "status": "pending",
        "created_at": now.isoformat(),
        "expires_at": (now + timedelta(seconds=timeout_s)).isoformat(),
        "responded_at": None,
        "responder": None,
    }
    _atomic_write(_path(task_id), record)
    return record


def read_pending(task_id: str) -> dict[str, Any] | None:
    path = _path(task_id)
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return None


def respond(task_id: str, decision: str, responder: str) -> dict[str, Any] | None:
    if decision not in ("approved", "rejected"):
        raise ValueError(f"decision must be 'approved' or 'rejected', got {decision!r}")
    record = read_pending(task_id)
    if record is None:
        return None
    record["status"] = decision
    record["responded_at"] = datetime.now(timezone.utc).isoformat()
    record["responder"] = responder
    _atomic_write(_path(task_id), record)
    return record


def mark_expired(task_id: str) -> dict[str, Any] | None:
    record = read_pending(task_id)
    if record is None:
        return None
    record["status"] = "expired"
    record["responded_at"] = datetime.now(timezone.utc).isoformat()
    _atomic_write(_path(task_id), record)
    return record


def list_pending() -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    d = _dir()
    if not d.exists():
        return out
    for f in sorted(d.glob("*.json")):
        try:
            rec = json.loads(f.read_text())
        except (json.JSONDecodeError, OSError):
            continue
        if rec.get("status") == "pending":
            out.append(rec)
    return out


def clear(task_id: str) -> None:
    try:
        _path(task_id).unlink()
    except FileNotFoundError:
        pass
