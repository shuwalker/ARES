"""Unit tests for the in-process SessionStore (volatile tier)."""

from ares.runtime.session_store import SessionStore


def test_record_and_history_round_trip():
    s = SessionStore(capacity=5)
    s.record("sess-1", "user", "hi", 1.0)
    s.record("sess-1", "assistant", "hello", 2.0)
    history = s.history("sess-1")
    assert [(t.role, t.text) for t in history] == [("user", "hi"), ("assistant", "hello")]


def test_capacity_evicts_oldest():
    s = SessionStore(capacity=3)
    for i in range(5):
        s.record("sess-1", "user", f"turn-{i}", float(i))
    history = s.history("sess-1")
    assert [t.text for t in history] == ["turn-2", "turn-3", "turn-4"]


def test_sessions_are_isolated():
    s = SessionStore(capacity=5)
    s.record("a", "user", "for-a", 1.0)
    s.record("b", "user", "for-b", 2.0)
    assert [t.text for t in s.history("a")] == ["for-a"]
    assert [t.text for t in s.history("b")] == ["for-b"]
    assert set(s.session_ids()) == {"a", "b"}


def test_empty_session_id_is_ignored():
    s = SessionStore()
    s.record("", "user", "ghost", 1.0)
    assert s.session_ids() == []


def test_clear_and_reset():
    s = SessionStore()
    s.record("a", "user", "1", 1.0)
    s.record("b", "user", "2", 2.0)
    s.clear("a")
    assert s.session_ids() == ["b"]
    s.reset()
    assert s.session_ids() == []
