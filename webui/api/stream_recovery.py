"""Replay-gap validation shared by WebSocket and compatibility SSE transports."""

from __future__ import annotations


def same_run_sequence(event_id: str | None, stream_id: str) -> int | None:
    from api.run_journal import _parse_run_journal_event_id

    run_id, sequence = _parse_run_journal_event_id(event_id)
    return sequence if run_id == stream_id else None


def assess_offline_gap(
    stream_id: str,
    after_event_id: str | None,
    snapshot: dict | None,
) -> tuple[bool, int | None, int]:
    """Return ``(safe, client_sequence, dropped_count)`` for a reconnect.

    A capped offline buffer may have evicted its oldest frames.  The retained
    tail is sent only when the durable journal proves the gap between the
    browser cursor and that tail is contiguous.  A cursor already inside the
    retained tail needs no journal bridge.
    """

    snapshot = dict(snapshot or {})
    try:
        dropped = max(0, int(snapshot.get("offline_dropped_events") or 0))
    except (TypeError, ValueError):
        dropped = 0
    cursor_seq = same_run_sequence(after_event_id, stream_id)
    if dropped <= 0:
        return True, cursor_seq, dropped

    first_seq = same_run_sequence(snapshot.get("offline_first_event_id"), stream_id)
    last_seq = same_run_sequence(snapshot.get("last_event_id"), stream_id)
    bridge_end = (first_seq - 1) if first_seq is not None else last_seq
    floor = max(0, int(cursor_seq or 0))
    if bridge_end is not None and floor >= bridge_end:
        return True, cursor_seq, dropped
    if bridge_end is None:
        return False, cursor_seq, dropped

    from api.run_journal import find_run_summary, read_run_events

    try:
        summary = find_run_summary(stream_id)
        if not summary:
            return False, cursor_seq, dropped
        journal = read_run_events(
            str(summary.get("session_id") or ""),
            stream_id,
            after_seq=floor,
            max_seq=bridge_end,
        )
    except Exception:
        return False, cursor_seq, dropped
    sequences = {
        int(entry.get("seq") or 0)
        for entry in journal.get("events") or []
        if isinstance(entry, dict) and floor < int(entry.get("seq") or 0) <= bridge_end
    }
    return len(sequences) == bridge_end - floor, cursor_seq, dropped


def recovery_payload(stream_id: str, session_id: str, dropped: int) -> dict:
    return {
        "type": "interrupted",
        "recovery_control": True,
        "message": (
            "The live replay buffer overflowed while no client was attached "
            "and the durable journal cannot backfill the missing frames."
        ),
        "hint": "The transcript was restored to the last saved state.",
        "session_id": session_id,
        "stream_id": stream_id,
        "offline_dropped_events": dropped,
    }


__all__ = ["assess_offline_gap", "recovery_payload", "same_run_sequence"]
