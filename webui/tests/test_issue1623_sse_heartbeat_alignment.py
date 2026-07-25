"""Realtime transports emit bounded application-level heartbeats."""

from pathlib import Path


REPO = Path(__file__).parent.parent


def test_realtime_heartbeat_constant_is_five_seconds_or_less():
    """WebSocket and SSE compatibility streams make progress while idle."""
    src = (REPO / "fastapi_app" / "routers" / "realtime.py").read_text(encoding="utf-8")

    # The constant must be defined.
    assert "_HEARTBEAT_SECONDS" in src, (
        "Named SSE heartbeat constant must exist (#1623)"
    )

    # Pull the literal value.
    import re
    m = re.search(r"_HEARTBEAT_SECONDS\s*=\s*([0-9.]+)", src)
    assert m, "Could not parse _HEARTBEAT_SECONDS literal"
    assert float(m.group(1)) <= 5.0


def test_no_sse_handler_uses_30s_or_higher_timeout():
    """No realtime handler should still be using the old
    30s/25s timeout. Every queue.get(timeout=...) call inside an SSE handler
    must reference the named constant, not a hard-coded number."""
    src = (REPO / "fastapi_app" / "routers" / "realtime.py").read_text(encoding="utf-8")

    import re
    # Catch q.get(timeout=30), subscriber.get(timeout=30), term.output.get(timeout=25), etc.
    bad = re.findall(r"\.get\(timeout=3[05]\)", src)
    assert not bad, (
        f"Found {len(bad)} SSE handler call(s) still using a 25/30s timeout: {bad}. "
        "All should use _SSE_HEARTBEAT_INTERVAL_SECONDS (#1623)."
    )


def test_realtime_queue_poll_uses_named_constant():
    src = (REPO / "fastapi_app" / "routers" / "realtime.py").read_text(encoding="utf-8")
    assert "subscriber.get, True, _HEARTBEAT_SECONDS" in src
    assert src.count("heartbeat") >= 4
