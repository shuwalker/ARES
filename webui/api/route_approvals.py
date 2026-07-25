"""Approval SSE state and helpers.

State-extraction prelude to the routes.py split tracked in #1907.
Extracts approval state, not handlers, by design.
"""

from __future__ import annotations

import queue
import threading
import uuid

from api.session_events import publish_session_list_changed

# Approval system (optional -- graceful fallback if agent not available)
try:
    from tools.approval import (
        submit_pending as _submit_pending_raw,
        approve_session,
        approve_permanent,
        save_permanent_allowlist,
        is_approved,
        _pending,
        _lock,
        _permanent_approved,
        _gateway_queues,
        resolve_gateway_approval,
        enable_session_yolo,
        disable_session_yolo,
        is_session_yolo_enabled,
    )
except ImportError:
    _submit_pending_raw = lambda *a, **k: None
    approve_session = lambda *a, **k: None
    approve_permanent = lambda *a, **k: None
    save_permanent_allowlist = lambda *a, **k: None
    is_approved = lambda *a, **k: True
    resolve_gateway_approval = lambda *a, **k: 0
    enable_session_yolo = lambda *a, **k: None
    disable_session_yolo = lambda *a, **k: None
    is_session_yolo_enabled = lambda *a, **k: False
    _pending = {}
    _lock = threading.Lock()
    _permanent_approved = set()
    _gateway_queues = {}


# ── Approval SSE subscribers (long-connection push) ──────────────────────────
_approval_sse_subscribers: dict[str, list[queue.Queue]] = {}
_GATEWAY_MIRROR_FLAG = "_gateway_mirror"
_GATEWAY_MIRROR_TOKEN = "_gateway_mirror_token"
_GATEWAY_ENTRY_DATA_TOKEN_KEY = "_webui_mirror_token"


def pending_snapshot(session_id: str) -> dict:
    """Return the oldest pending approval without exposing transport state."""
    with _lock:
        reconcile_gateway_pending_mirror_locked(session_id)
        entries = _pending.get(session_id)
        if isinstance(entries, list):
            pending = entries[0] if entries else None
            count = len(entries)
        elif entries:
            pending, count = entries, 1
        else:
            pending, count = None, 0
        if pending is None:
            gateway_entries = _gateway_queues.get(session_id) or []
            if gateway_entries:
                data = getattr(gateway_entries[0], "data", None) or {}
                if data:
                    pending, count = data, len(gateway_entries)
    return {"pending": dict(pending) if pending else None, "pending_count": count}


def _approval_sse_subscribe(session_id: str) -> queue.Queue:
    """Register an SSE subscriber for approval events on a given session."""
    q = queue.Queue(maxsize=16)
    with _lock:
        _approval_sse_subscribers.setdefault(session_id, []).append(q)
    return q


def approval_sse_subscribe_with_snapshot(session_id: str) -> tuple[queue.Queue, dict]:
    """Atomically subscribe before reading the initial approval snapshot."""

    q = queue.Queue(maxsize=16)
    with _lock:
        _approval_sse_subscribers.setdefault(session_id, []).append(q)
        reconcile_gateway_pending_mirror_locked(session_id)
        entries = _pending.get(session_id)
        if isinstance(entries, list):
            pending = entries[0] if entries else None
            count = len(entries)
        elif entries:
            pending, count = entries, 1
        else:
            pending, count = None, 0
        if pending is None:
            gateway_entries = _gateway_queues.get(session_id) or []
            if gateway_entries:
                data = getattr(gateway_entries[0], "data", None) or {}
                if data:
                    pending, count = data, len(gateway_entries)
        snapshot = {
            "pending": dict(pending) if pending else None,
            "pending_count": count,
        }
    return q, snapshot


def _approval_sse_unsubscribe(session_id: str, q: queue.Queue) -> None:
    """Remove an SSE subscriber."""
    with _lock:
        subs = _approval_sse_subscribers.get(session_id)
        if subs and q in subs:
            subs.remove(q)
            if not subs:
                _approval_sse_subscribers.pop(session_id, None)


def _approval_sse_notify_locked(session_id: str, head: dict | None, total: int) -> None:
    """Push an approval event to all SSE subscribers for a session.

    CALLER MUST HOLD `_lock`. Snapshots the subscriber list under the held
    lock and then calls `q.put_nowait()` on each (which is itself thread-safe).

    `head` is the approval entry currently at the head of the queue (the one
    the UI should display) — NOT the just-appended entry. With multiple
    parallel approvals (#527), the just-appended entry is at the TAIL, but
    `/api/approval/pending` always returns the HEAD, so SSE must match.

    `total` is the total number of pending approvals.

    Pass `head=None` and `total=0` when the queue has just been emptied (e.g.
    `_handle_approval_respond` popped the last entry) so the client knows to
    hide its approval card.
    """
    payload = {"pending": dict(head) if head else None, "pending_count": total}
    subs = _approval_sse_subscribers.get(session_id, ())
    for q in subs:
        try:
            q.put_nowait(payload)
        except queue.Full:
            pass  # drop if subscriber is slow (bounded queue prevents memory leak)


def _approval_sse_notify(session_id: str, head: dict | None, total: int) -> None:
    """Convenience wrapper that takes `_lock` itself.

    Use only from contexts that don't already hold `_lock`. Production call
    sites (submit_pending, _handle_approval_respond) MUST hold the lock and
    call `_approval_sse_notify_locked` directly to avoid a notify-ordering
    race where a later append's notify can fire before an earlier append's
    notify (resulting in stale `pending_count`).
    """
    with _lock:
        _approval_sse_notify_locked(session_id, head, total)


def _gateway_mirror_entry_token(entry) -> str:
    """Return a stable token for the current process lifetime of a gateway head.

    Stamps a token key into the entry's `.data` dict so
    slotted objects like `_ApprovalEntry` work without attribute mutation
    and the token survives CPython `id()` reuse after GC.
    """
    data = getattr(entry, "data", None)
    if isinstance(data, dict):
        token = data.get(_GATEWAY_ENTRY_DATA_TOKEN_KEY)
        if not token:
            token = uuid.uuid4().hex
            data[_GATEWAY_ENTRY_DATA_TOKEN_KEY] = token
        return token
    return uuid.uuid4().hex


def _is_gateway_mirror_entry(entry: dict | None) -> bool:
    return isinstance(entry, dict) and bool(entry.get(_GATEWAY_MIRROR_FLAG))


def _normalize_pending_queue_locked(session_key: str) -> list[dict]:
    """Return the session's polling queue as a mutable list under `_lock`."""
    queue_list = _pending.setdefault(session_key, [])
    if not isinstance(queue_list, list):
        _pending[session_key] = [queue_list]
        queue_list = _pending[session_key]
    return queue_list


def reconcile_gateway_pending_mirror_locked(session_key: str) -> tuple[dict | None, int, bool]:
    """Purge stale gateway mirrors and ensure at most one live head mirror exists.

    CALLER MUST HOLD `_lock`.
    """
    changed = False
    queue_list = list(_normalize_pending_queue_locked(session_key))
    live_gateway_queue = _gateway_queues.get(session_key) or []

    live_head_entry = live_gateway_queue[0] if live_gateway_queue else None
    live_head_data = getattr(live_head_entry, "data", None) or {}
    live_token = _gateway_mirror_entry_token(live_head_entry) if live_head_entry and live_head_data else None

    rebuilt: list[dict] = []
    live_mirror_present = False
    for entry in queue_list:
        if not _is_gateway_mirror_entry(entry):
            rebuilt.append(entry)
            continue
        if live_token and entry.get(_GATEWAY_MIRROR_TOKEN) == live_token and not live_mirror_present:
            rebuilt.append(entry)
            live_mirror_present = True
            continue
        changed = True

    if live_token and not live_mirror_present:
        mirror_entry = dict(live_head_data)
        mirror_entry.setdefault("approval_id", uuid.uuid4().hex)
        mirror_entry[_GATEWAY_MIRROR_FLAG] = True
        mirror_entry[_GATEWAY_MIRROR_TOKEN] = live_token
        rebuilt.append(mirror_entry)
        live_mirror_present = True
        changed = True

    if rebuilt:
        if rebuilt != queue_list:
            _pending[session_key] = rebuilt
            changed = True
    else:
        if session_key in _pending:
            _pending.pop(session_key, None)
            changed = True

    head = rebuilt[0] if rebuilt else None
    total = len(rebuilt)
    return head, total, changed


def _gateway_mirrored_pending_run_id(session_key: str, approval_id: str) -> str | None:
    """Return the mirrored gateway approval run_id for a matching pending card.

    Reconciles the mirror first so a live gateway head still survives a lost
    `active_stream_id` pointer.
    """
    approval_id = str(approval_id or "").strip()
    if not approval_id:
        return None
    with _lock:
        reconcile_gateway_pending_mirror_locked(session_key)
        queue = _pending.get(session_key)
        if isinstance(queue, list):
            entries = queue
        elif queue:
            entries = [queue]
        else:
            return None
        for entry in entries:
            if isinstance(entry, dict) and entry.get("approval_id") == approval_id and entry.get(_GATEWAY_MIRROR_FLAG):
                run_id = str(entry.get("run_id") or "").strip()
                return run_id or None
    return None


def submit_gateway_pending_mirror(session_key: str, approval: dict) -> None:
    """Mirror the live gateway head into WebUI polling state under a typed tag."""
    del approval  # mirror from the live gateway head under `_lock`, not from callback input
    with _lock:
        head, total, _changed = reconcile_gateway_pending_mirror_locked(session_key)
        _approval_sse_notify_locked(session_key, head, total)
    publish_session_list_changed("attention_pending")


def submit_pending(session_key: str, approval: dict) -> None:
    """Append a pending approval to the per-session queue.

    Wraps the agent's submit_pending to:
    - Add a stable approval_id (uuid4 hex) so the respond endpoint can target
      a specific entry even when multiple approvals are queued simultaneously.
    - Change the storage from a single overwriting dict value to a list, so
      parallel tool calls each get their own approval slot (fixes #527).
    - Notify any connected SSE subscribers immediately.
    """
    entry = dict(approval)
    entry.setdefault("approval_id", uuid.uuid4().hex)
    with _lock:
        queue_list = _normalize_pending_queue_locked(session_key)
        queue_list.append(entry)
        total = len(queue_list)
        head = queue_list[0]  # /api/approval/pending always returns head
        # Push to SSE subscribers from inside _lock so two parallel
        # submit_pending calls can't deliver out-of-order (T2's later
        # notify arriving before T1's earlier notify with a stale count).
        _approval_sse_notify_locked(session_key, head, total)
    publish_session_list_changed("attention_pending")
    # NOTE: We do NOT call _submit_pending_raw here — that function overwrites
    # _pending[session_key] with a single dict, which would undo the list we just
    # built. The gateway blocking path uses _gateway_queues (a separate mechanism
    # managed by check_all_command_guards / register_gateway_notify), which is
    # unaffected by _pending. The _pending dict is only used for UI polling.


def resolve_approval_legacy(session_id: str, approval_id: str, choice: str) -> bool:
    """Resolve one local approval while preserving queued-card ordering."""

    pending = None
    found_target = False
    gateway_keys = []
    with _lock:
        reconcile_gateway_pending_mirror_locked(session_id)
        queue_list = _pending.get(session_id)
        if isinstance(queue_list, list):
            if approval_id:
                for index, entry in enumerate(queue_list):
                    if entry.get("approval_id") == approval_id:
                        pending = queue_list.pop(index)
                        found_target = True
                        break
            else:
                pending = queue_list.pop(0) if queue_list else None
                found_target = pending is not None
            if not queue_list:
                _pending.pop(session_id, None)
        elif queue_list and (not approval_id or queue_list.get("approval_id") == approval_id):
            pending = _pending.pop(session_id, None)
            found_target = pending is not None

        if not pending and not approval_id:
            gateway_queue = _gateway_queues.get(session_id)
            if gateway_queue:
                data = getattr(gateway_queue[0], "data", None) or {}
                gateway_keys = data.get("pattern_keys") or [data.get("pattern_key", "")]
                found_target = True
        remaining = _pending.get(session_id)
        if isinstance(remaining, list) and remaining:
            _approval_sse_notify_locked(session_id, remaining[0], len(remaining))
        else:
            _approval_sse_notify_locked(session_id, None, 0)

    pending_keys = pending.get("pattern_keys") or [pending.get("pattern_key", "")] if pending else []
    keys = [key for key in [*pending_keys, *gateway_keys] if key]
    if choice in {"once", "session"}:
        for key in keys:
            approve_session(session_id, key)
    elif choice == "always":
        for key in keys:
            approve_session(session_id, key)
            approve_permanent(key)
        save_permanent_allowlist(_permanent_approved)
    gateway_resolved = (
        resolve_gateway_approval(session_id, choice, resolve_all=False)
        if found_target or not approval_id
        else 0
    )
    if approval_id:
        try:
            from api.os_automation_consent import signal_decision

            signal_decision(approval_id, choice)
        except Exception:
            pass
    resolved = bool(pending) or bool(gateway_resolved) or not bool(approval_id)
    if resolved:
        publish_session_list_changed("attention_resolved")
    return resolved


def _gateway_pending_without_run_id(session_id: str, approval_id: str) -> bool:
    with _lock:
        reconcile_gateway_pending_mirror_locked(session_id)
        entries = _pending.get(session_id)
        entries = entries if isinstance(entries, list) else ([entries] if entries else [])
        if approval_id:
            return any(
                isinstance(entry, dict)
                and entry.get("approval_id") == approval_id
                and entry.get(_GATEWAY_MIRROR_FLAG)
                for entry in entries
            )
        return bool(entries and isinstance(entries[0], dict) and entries[0].get(_GATEWAY_MIRROR_FLAG))


def _session_has_pending_approval(session_id: str) -> bool:
    with _lock:
        reconcile_gateway_pending_mirror_locked(session_id)
        return bool(_pending.get(session_id) or _gateway_queues.get(session_id))


def respond_approval(session_id: str, approval_id: str, choice: str) -> tuple[dict, int]:
    """Resolve a local or gateway approval and return its established wire shape."""

    if choice not in {"once", "session", "always", "deny"}:
        return {"error": f"Invalid choice: {choice}"}, 400
    try:
        from api.config import get_config
        from api.gateway_chat import (
            _STREAM_RUN_IDS,
            _gateway_api_key,
            _gateway_base_url,
            webui_gateway_chat_enabled,
        )
        from api.models import get_session

        session = get_session(session_id)
        run_id = None
        active_stream_id = getattr(session, "active_stream_id", None)
        if active_stream_id:
            run_id = _STREAM_RUN_IDS.get(active_stream_id)
        if not run_id and approval_id:
            run_id = _gateway_mirrored_pending_run_id(session_id, approval_id)
        if run_id:
            if not approval_id:
                return {"error": "approval_id is required for gateway approvals"}, 400
            from api.runner_client import HttpRunnerClient, RunnerClientError

            try:
                HttpRunnerClient(
                    base_url=_gateway_base_url(get_config()),
                    api_key=_gateway_api_key(),
                ).respond_approval(run_id, approval_id, choice)
            except (RunnerClientError, ValueError) as exc:
                return {"ok": False, "choice": choice, "relayed": True, "error": str(exc)}, 502
            resolve_approval_legacy(session_id, approval_id, choice)
            return {"ok": True, "choice": choice, "relayed": True}, 200
        if webui_gateway_chat_enabled(get_config()) and _gateway_pending_without_run_id(
            session_id, approval_id
        ):
            return {
                "ok": False,
                "choice": choice,
                "relayed": False,
                "code": "gateway_run_unavailable",
                "error": (
                    "Gateway approval could not be relayed because the active run is unavailable. "
                    "Reopen the session or retry after it reconnects."
                ),
            }, 409
    except Exception:
        pass

    from api.runtime_adapter import LegacyJournalRuntimeAdapter, runtime_adapter_enabled

    accepted = (
        LegacyJournalRuntimeAdapter(approval_delegate=resolve_approval_legacy)
        .respond_approval(session_id, approval_id, choice)
        .accepted
        if runtime_adapter_enabled()
        else resolve_approval_legacy(session_id, approval_id, choice)
    )
    if not accepted and not _session_has_pending_approval(session_id):
        return {"ok": True, "choice": choice, "stale_cleared": True}, 200
    return {"ok": accepted, "choice": choice}, 200
