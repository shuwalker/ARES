"""Deny-by-default consent gate for OS-automation execution (osascript/AppleScript).

System-category native actions (AppleScript/JXA via osascript) must not run
without the user's explicit consent. This module submits an approval card onto
the existing per-session approval queue (see `route_approvals`) and blocks the
calling automation turn until the user resolves it. If no decision arrives
before the timeout, or if the approval transport is unavailable, the action is
DENIED — the inverse of the legacy `is_approved -> True` fallback.
"""

from __future__ import annotations

import threading
import uuid
from dataclasses import dataclass

# Bounded wait for a human decision before an OS-automation action is denied.
CONSENT_TIMEOUT_SECONDS = 60.0

_APPROVE_CHOICES = {"once", "session", "always"}

# approval_id -> (Event, result-box). The event is set when the matching
# approval is resolved; the box carries the chosen decision string.
_waiters: dict[str, "_ConsentWaiter"] = {}
_waiters_lock = threading.Lock()


@dataclass
class _ConsentWaiter:
    event: threading.Event
    choice: str | None = None


def signal_decision(approval_id: str, choice: str) -> None:
    """Wake a blocked OS-automation turn with the user's decision.

    Called from the approval-resolution path. Safe to call for approval_ids
    that were not registered here (no-op).
    """
    approval_id = str(approval_id or "").strip()
    if not approval_id:
        return
    with _waiters_lock:
        waiter = _waiters.get(approval_id)
        if waiter is None:
            return
        waiter.choice = str(choice or "").strip().lower()
        waiter.event.set()


def require_os_automation_consent(session_id: str, action_description: str) -> bool:
    """Block until the user approves this OS-automation action; deny otherwise.

    Returns True only when the user explicitly approves (once/session/always).
    Returns False on explicit denial, on timeout, or when the approval queue
    cannot be reached — deny-by-default.
    """
    session_id = str(session_id or "").strip()
    if not session_id:
        # No session means no channel to ask the user — refuse.
        return False

    approval_id = uuid.uuid4().hex
    waiter = _ConsentWaiter(event=threading.Event())
    with _waiters_lock:
        _waiters[approval_id] = waiter

    try:
        try:
            from api.route_approvals import submit_pending
        except Exception:
            # No approval transport available — deny rather than run ungated.
            return False

        card = {
            "approval_id": approval_id,
            "kind": "os_automation",
            "tool": "os_automation",
            "title": "Allow OS automation?",
            "description": action_description,
            "pattern_key": f"os_automation:{action_description}",
        }
        try:
            submit_pending(session_id, card)
        except Exception:
            return False

        if not waiter.event.wait(timeout=CONSENT_TIMEOUT_SECONDS):
            # No decision in time — deny and clear the stale card.
            _cleanup_pending(session_id, approval_id)
            return False

        return (waiter.choice or "") in _APPROVE_CHOICES
    finally:
        with _waiters_lock:
            _waiters.pop(approval_id, None)


def _cleanup_pending(session_id: str, approval_id: str) -> None:
    """Best-effort removal of a timed-out approval card from the queue."""
    try:
        from api.route_approvals import resolve_approval_legacy

        resolve_approval_legacy(session_id, approval_id, "deny")
    except Exception:
        pass
