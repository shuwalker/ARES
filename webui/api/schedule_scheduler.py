"""Execution bridge for ARES-owned schedules."""

from __future__ import annotations

import os
from pathlib import Path
import threading
from typing import Any


_ares_home = Path(os.environ.get("ARES_HOME", "~/.ares")).expanduser()
_LOCK_DIR = _ares_home / "cron"
_LOCK_FILE = _LOCK_DIR / ".tick.lock"
_KNOWN_DELIVERY_PLATFORMS = frozenset({"telegram", "discord", "slack", "feishu"})
SILENT_MARKER = "[SILENT]"
_RUN_LOCK = threading.Lock()


def run_job(job: dict[str, Any]) -> tuple[bool, str, str, str | None]:
    """Execute a schedule through the explicitly elected external runtime."""
    from api.backend_selector import get_active_backend
    from api.backends.router import get_router
    from api.config import get_config

    runtime_id = get_active_backend(get_config())
    if not runtime_id:
        message = "No default external runtime is selected."
        return False, message, "", message
    backend = get_router().backends.get(runtime_id)
    if backend is None or not backend.is_available():
        message = f"Selected runtime is unavailable: {runtime_id}"
        return False, message, "", message
    try:
        with _RUN_LOCK:
            result = backend.run_turn(
                str(job.get("prompt") or ""),
                f"schedule:{job.get('id') or 'unknown'}",
                model=job.get("model"),
                model_provider=job.get("provider"),
            )
    except Exception as exc:
        message = f"Schedule runtime failed: {type(exc).__name__}"
        return False, message, "", message
    error = str((result or {}).get("error") or "").strip()
    text = str((result or {}).get("text") or "").strip()
    if error:
        return False, error, "", error
    return True, text, text, None


def _deliver_result(job: dict[str, Any], content: str) -> str | None:
    """Local delivery is persisted by ARES; channel delivery is adapter-owned."""
    delivery = str(job.get("deliver") or "local").strip().lower()
    if delivery in {"", "local", "origin"}:
        return None
    return f"Delivery adapter is not configured for {delivery}."
