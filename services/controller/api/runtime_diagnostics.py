"""Non-sensitive diagnostics for runtime-owned stream channels."""

from __future__ import annotations


def stream_runtime_diagnostics() -> dict:
    from api.config import STREAMS, STREAMS_LOCK

    with STREAMS_LOCK:
        items = list(STREAMS.items())
    rows = []
    subscribers = 0
    buffered = 0
    for stream_id, channel in items:
        try:
            snapshot = channel.diagnostic_snapshot()
            snapshot = snapshot if isinstance(snapshot, dict) else {}
        except Exception:
            snapshot = {}
        subscriber_count = int(snapshot.get("subscriber_count") or 0)
        offline_count = int(snapshot.get("offline_buffered_events") or 0)
        subscribers += subscriber_count
        buffered += offline_count
        rows.append(
            {
                "stream_id": str(stream_id),
                "subscriber_count": subscriber_count,
                "offline_buffered_events": offline_count,
            }
        )
    rows.sort(key=lambda row: row["stream_id"])
    return {
        "active_streams": len(rows),
        "total_subscribers": subscribers,
        "total_offline_buffered_events": buffered,
        "streams": rows,
    }


_stream_runtime_diagnostics = stream_runtime_diagnostics


__all__ = ["stream_runtime_diagnostics"]
