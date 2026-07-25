from api.config import create_stream_channel


def test_stream_channel_broadcasts_each_event_to_every_subscriber():
    stream = create_stream_channel()
    q1 = stream.subscribe()
    q2 = stream.subscribe()

    try:
        stream.put_nowait(("token", {"text": "H"}))
        stream.put_nowait(("token", {"text": "allo"}))
        stream.put_nowait(("stream_end", {"status": "done"}))

        assert q1.get(timeout=1) == ("token", {"text": "H"})
        assert q1.get(timeout=1) == ("token", {"text": "allo"})
        assert q1.get(timeout=1) == ("stream_end", {"status": "done"})

        assert q2.get(timeout=1) == ("token", {"text": "H"})
        assert q2.get(timeout=1) == ("token", {"text": "allo"})
        assert q2.get(timeout=1) == ("stream_end", {"status": "done"})
    finally:
        stream.unsubscribe(q1)
        stream.unsubscribe(q2)


def test_late_second_tab_receives_the_offline_snapshot():
    stream = create_stream_channel()
    stream.put_nowait(("token", {"text": "offline"}))
    first, first_snapshot = stream.subscribe_with_snapshot()
    second, second_snapshot = stream.subscribe_with_snapshot()
    try:
        assert first_snapshot["offline_buffered_events"] == 1
        assert stream.diagnostic_snapshot()["subscriber_count"] == 2
        stream.put_nowait(("stream_end", {"status": "done"}))
        assert first.get(timeout=1)[0] == "token"
        assert second.get(timeout=1)[0] == "token"
        assert first.get(timeout=1)[0] == "stream_end"
        assert second.get(timeout=1)[0] == "stream_end"
    finally:
        stream.unsubscribe(first)
        stream.unsubscribe(second)
