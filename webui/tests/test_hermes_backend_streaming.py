from __future__ import annotations

import queue
import threading

from api.backends.hermes_streaming import _finish_hermes_stream
from api.streaming import STREAMS, STREAMS_LOCK


class RecordingJournal:
    def __init__(self) -> None:
        self.events: list[tuple[str, object]] = []
        self.closed = False

    def append_sse_event(self, name: str, payload: object) -> dict[str, str]:
        self.events.append((name, payload))
        return {"event_id": "hermes-terminal-regression:2"}

    def close(self) -> None:
        self.closed = True


def test_finish_hermes_stream_emits_canonical_terminal_event() -> None:
    stream_id = "hermes-terminal-regression"
    events: queue.Queue = queue.Queue()
    with STREAMS_LOCK:
        STREAMS[stream_id] = events

    _finish_hermes_stream(
        stream_id,
        "missing-session",
        events,
        run_journal=None,
        cancel_event=threading.Event(),
    )

    emitted = []
    while not events.empty():
        emitted.append(events.get_nowait()[0])

    assert "stream_end" in emitted


def test_finish_hermes_stream_persists_terminal_event_for_reconnect() -> None:
    stream_id = "hermes-terminal-regression"
    events: queue.Queue = queue.Queue()
    journal = RecordingJournal()
    with STREAMS_LOCK:
        STREAMS[stream_id] = events

    _finish_hermes_stream(
        stream_id,
        "missing-session",
        events,
        run_journal=journal,
        cancel_event=threading.Event(),
    )

    assert [name for name, _payload in journal.events] == ["stream_end"]
    assert journal.closed is True
