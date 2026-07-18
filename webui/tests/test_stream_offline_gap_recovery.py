"""Offline-buffer truncation must never produce a silently incomplete stream."""

from __future__ import annotations

from api.run_journal import append_run_event
from api.stream_recovery import assess_offline_gap, recovery_payload


def _snapshot(*, first="run-1:9", last="run-1:10", dropped=25):
    return {
        "offline_dropped_events": dropped,
        "offline_first_event_id": first,
        "last_event_id": last,
    }


def test_missing_journal_rejects_truncated_tail(tmp_path, monkeypatch):
    import api.models

    monkeypatch.setattr(api.models, "SESSION_DIR", tmp_path)
    safe, cursor, dropped = assess_offline_gap("run-1", "run-1:2", _snapshot())
    assert safe is False
    assert cursor == 2
    payload = recovery_payload("run-1", "session-1", dropped)
    assert payload["recovery_control"] is True
    assert payload["offline_dropped_events"] == 25


def test_contiguous_journal_bridge_allows_retained_tail(tmp_path, monkeypatch):
    import api.models

    monkeypatch.setattr(api.models, "SESSION_DIR", tmp_path)
    for seq in range(1, 11):
        append_run_event(
            "session-1",
            "run-1",
            "token",
            {"text": str(seq)},
            session_dir=tmp_path,
            seq=seq,
        )
    safe, cursor, dropped = assess_offline_gap("run-1", "run-1:2", _snapshot())
    assert (safe, cursor, dropped) == (True, 2, 25)


def test_hole_in_journal_rejects_tail(tmp_path, monkeypatch):
    import api.models

    monkeypatch.setattr(api.models, "SESSION_DIR", tmp_path)
    for seq in (1, 2, 3, 5, 6, 7, 8):
        append_run_event(
            "session-1",
            "run-1",
            "token",
            {"text": str(seq)},
            session_dir=tmp_path,
            seq=seq,
        )
    assert assess_offline_gap("run-1", "run-1:2", _snapshot())[0] is False


def test_cursor_inside_retained_tail_requires_no_journal(tmp_path, monkeypatch):
    import api.models

    monkeypatch.setattr(api.models, "SESSION_DIR", tmp_path)
    safe, cursor, _dropped = assess_offline_gap("run-1", "run-1:9", _snapshot())
    assert safe is True
    assert cursor == 9


def test_unknown_cutoff_fails_closed_when_frames_were_dropped():
    assert assess_offline_gap(
        "run-1",
        "run-1:2",
        _snapshot(first=None, last=None),
    )[0] is False


def test_no_eviction_needs_no_journal_proof():
    assert assess_offline_gap("run-1", "run-1:2", _snapshot(dropped=0))[0] is True
