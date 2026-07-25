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
    """Deliver a schedule's result to its destination.

    Local delivery is persisted by ARES (the caller writes the output), so this
    returns None (success) for local/origin destinations. Channel delivery is
    dispatched to a configured delivery adapter. If the destination is a known
    platform but no adapter is configured for it, an error string is returned so
    the caller records the delivery failure honestly — ARES never claims a
    channel delivery succeeded when no adapter actually sent it.
    """
    delivery = str(job.get("deliver") or "local").strip().lower()
    if delivery in {"", "local", "origin"}:
        return None

    if delivery not in _KNOWN_DELIVERY_PLATFORMS:
        return f"Unknown delivery destination: {delivery}."

    adapter = _resolve_delivery_adapter(delivery)
    if adapter is None:
        return (
            f"Delivery adapter is not configured for {delivery}. "
            f"Configure a {delivery} delivery connection to enable channel delivery."
        )

    target = str(job.get("deliver_target") or "").strip()
    if not target:
        return f"No delivery target configured for {delivery}."

    try:
        adapter(target=target, content=content, job=job)
    except Exception as exc:  # pragma: no cover - adapter-specific failures
        return f"Delivery to {delivery} failed: {type(exc).__name__}"
    return None


def _resolve_delivery_adapter(platform: str):
    """Return a callable delivery adapter for a platform, or None if unconfigured.

    Adapters are looked up from the optional `api.delivery_adapters` registry so
    channel delivery stays adapter-owned and detected, never hardcoded. A missing
    registry or missing platform adapter means "not configured" (deny/skip), not
    a silent success.
    """
    try:
        from api.delivery_adapters import get_delivery_adapter
    except Exception:
        return None
    try:
        return get_delivery_adapter(platform)
    except Exception:
        return None
