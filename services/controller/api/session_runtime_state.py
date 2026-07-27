"""Session run-state reconciliation independent of an HTTP transport."""

from __future__ import annotations

import logging
import time


logger = logging.getLogger(__name__)


def clear_stale_stream_state(session) -> bool:
    """Clear persisted run flags only after proving no worker still owns them."""
    from api.config import (
        ACTIVE_RUNS,
        ACTIVE_RUNS_LOCK,
        STREAMS,
        STREAMS_LOCK,
        _get_session_agent_lock,
    )

    stream_id = getattr(session, "active_stream_id", None)
    if not stream_id:
        return False
    with STREAMS_LOCK:
        if stream_id in STREAMS:
            return False
    with ACTIVE_RUNS_LOCK:
        if stream_id in (ACTIVE_RUNS or {}):
            return False
    try:
        from api.models import _REPAIR_STALE_PENDING_GRACE_SECONDS

        grace_seconds = float(_REPAIR_STALE_PENDING_GRACE_SECONDS)
        started = getattr(session, "pending_started_at", None)
        age = time.time() - float(started) if started else None
    except Exception:
        grace_seconds, age = 30.0, None
    if getattr(session, "pending_user_message", None) and age is not None and age < grace_seconds:
        return False

    original = session
    if getattr(session, "_loaded_metadata_only", False):
        try:
            from api.models import get_session

            session = get_session(session.session_id, metadata_only=False)
        except Exception:
            logger.warning(
                "Refused to clear stale stream %s for %s without a full session load",
                stream_id,
                getattr(original, "session_id", "?"),
            )
            return False
        if not getattr(session, "active_stream_id", None):
            _clear_runtime_fields(original)
            return False

    with _get_session_agent_lock(session.session_id):
        if getattr(session, "active_stream_id", None) != stream_id:
            return False
        if getattr(session, "pending_user_message", None):
            try:
                from api.models import _apply_core_sync_or_error_marker, _get_profile_home

                core_path = _get_profile_home(getattr(session, "profile", None)) / "sessions" / f"session_{session.session_id}.json"
                repaired = _apply_core_sync_or_error_marker(
                    session,
                    core_path,
                    stream_id_for_recheck=stream_id,
                    touch_updated_at=False,
                )
            except Exception:
                logger.exception("Failed to repair stale pending stream %s", stream_id)
                repaired = False
            if repaired:
                if original is not session:
                    _clear_runtime_fields(original)
                return True
            if getattr(session, "active_stream_id", None) != stream_id:
                return False
        from api.streaming import _materialize_pending_user_turn_before_error

        _materialize_pending_user_turn_before_error(session)
        _clear_runtime_fields(session)
        try:
            session.save(touch_updated_at=False)
        except Exception:
            logger.exception("Failed to persist stale-stream cleanup for %s", session.session_id)
    if original is not session:
        _clear_runtime_fields(original)
    return True


def _clear_runtime_fields(session) -> None:
    session.active_stream_id = None
    if hasattr(session, "pending_user_message"):
        session.pending_user_message = None
    if hasattr(session, "pending_attachments"):
        session.pending_attachments = []
    if hasattr(session, "pending_started_at"):
        session.pending_started_at = None
    if hasattr(session, "pending_user_source"):
        session.pending_user_source = None


_clear_stale_stream_state = clear_stale_stream_state


def reconcile_stale_stream_state_for_session_rows(session_rows) -> bool:
    """Repair dead run flags advertised by persisted sidebar rows."""
    from api.models import get_session

    changed = False
    for row in session_rows or []:
        if not isinstance(row, dict):
            continue
        session_id = row.get("session_id")
        if not session_id or not row.get("active_stream_id") or row.get("is_streaming") is True:
            continue
        try:
            session = get_session(session_id, metadata_only=True)
        except Exception:
            logger.debug("Could not load %s for stale run reconciliation", session_id, exc_info=True)
            continue
        changed = clear_stale_stream_state(session) or changed
    return changed


_reconcile_stale_stream_state_for_session_rows = reconcile_stale_stream_state_for_session_rows


__all__ = ["clear_stale_stream_state", "reconcile_stale_stream_state_for_session_rows"]
