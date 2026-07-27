"""Regression test: _handle_clarify_sse_stream must not deadlock on its own lock.

The naive implementation called clarify.get_pending(sid) inside a
`with _clarify_lock:` block, but get_pending also acquires _lock.  Because
clarify._lock is a non-reentrant threading.Lock(), the second acquisition
would deadlock the SSE handler thread the moment any client connected to
/api/clarify/stream.

This test runs the inlined snapshot logic under the lock and verifies it
completes — both with an empty queue and with a pending entry — within a
short timeout.  If the regression returns (someone re-introduces the
recursive get_pending() call), this test will hang and the timeout will
fire.
"""

from __future__ import annotations

import pathlib
import queue
import sys
import threading
import time

REPO_ROOT = pathlib.Path(__file__).parent.parent.resolve()
sys.path.insert(0, str(REPO_ROOT))


def _run_handler_snapshot(sid: str, timeout: float = 2.0):
    """Replicate the snapshot logic from _handle_clarify_sse_stream and
    return ``(initial_pending, initial_count)`` or raise on deadlock."""
    from api.clarify import (
        _lock as _clarify_lock,
        _clarify_sse_subscribers as _clarify_subs,
        _gateway_queues as _clarify_gateway_queues,
        _pending as _clarify_pending,
    )

    result: list = []

    def worker():
        try:
            q: queue.Queue = queue.Queue(maxsize=16)
            initial_pending = None
            initial_count = 0
            with _clarify_lock:
                _clarify_subs.setdefault(sid, []).append(q)
                gw_q = _clarify_gateway_queues.get(sid) or []
                if gw_q:
                    initial_pending = dict(gw_q[0].data)
                    initial_count = len(gw_q)
                else:
                    legacy = _clarify_pending.get(sid)
                    if legacy:
                        initial_pending = dict(legacy)
                        initial_count = 1
            # Cleanup the subscriber so we don't leak between tests.
            with _clarify_lock:
                subs = _clarify_subs.get(sid)
                if subs and q in subs:
                    subs.remove(q)
                    if not subs:
                        _clarify_subs.pop(sid, None)
            result.append((initial_pending, initial_count))
        except BaseException as exc:  # noqa: BLE001
            result.append(exc)

    t = threading.Thread(target=worker, daemon=True)
    t.start()
    t.join(timeout=timeout)
    if t.is_alive():
        raise AssertionError(
            f"_handle_clarify_sse_stream snapshot deadlocked (>{timeout}s). "
            "Did someone re-introduce a recursive _lock acquisition? "
            "The handler must NOT call clarify.get_pending() — read "
            "_gateway_queues / _pending inline under the same _lock."
        )
    if isinstance(result[0], BaseException):
        raise result[0]
    return result[0]


def test_handler_snapshot_does_not_deadlock_when_queue_is_empty():
    sid = f"clarify-sse-empty-{time.time_ns()}"
    initial_pending, initial_count = _run_handler_snapshot(sid)
    assert initial_pending is None
    assert initial_count == 0


def test_handler_snapshot_does_not_deadlock_when_queue_has_entry():
    """With a real pending entry, the snapshot must capture it without deadlock."""
    from api import clarify

    sid = f"clarify-sse-populated-{time.time_ns()}"
    try:
        clarify.submit_pending(sid, {
            "question": "Pick one?",
            "choices_offered": ["a", "b"],
        })
        initial_pending, initial_count = _run_handler_snapshot(sid)
        assert initial_count == 1
        assert initial_pending is not None
        assert initial_pending.get("question") == "Pick one?"
        assert initial_pending.get("choices_offered") == ["a", "b"]
    finally:
        clarify.resolve_clarify(sid, "a")


def test_fastapi_handler_uses_public_clarify_subscription_api():
    """The ASGI handler must not acquire clarify's private lock itself."""
    src = (REPO_ROOT / "fastapi_app" / "routers" / "realtime.py").read_text(encoding="utf-8")
    start = src.find("async def clarification_events_sse(")
    assert start != -1
    end = src.find("\n@router.", start + 1)
    body = src[start:end if end != -1 else len(src)]
    assert "sse_subscribe(session_id)" in body
    assert "get_pending(session_id)" in body
    assert "_clarify_lock" not in body
