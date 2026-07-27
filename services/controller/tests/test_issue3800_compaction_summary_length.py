"""
Regression coverage for compaction summary normalization (#3800).
"""

import sys
import types

from api.manual_compression import compress_session
from api.models import get_session
from api.streaming import _compact_summary_text
from tests.test_sprint46 import (
    _FakeAgent,
    _install_fake_compression_runtime,
    _make_session,
)


def _install_manual_summary(monkeypatch, summary_text):
    agent_module = types.ModuleType("agent")
    agent_module.__path__ = []
    feedback_module = types.ModuleType("agent.manual_compression_feedback")
    feedback_module.summarize_manual_compression = (
        lambda original_messages, compressed_messages, before_count, after_count: {
            "reference_message": summary_text,
        }
    )
    monkeypatch.setitem(sys.modules, "agent", agent_module)
    monkeypatch.setitem(sys.modules, "agent.manual_compression_feedback", feedback_module)


def _run_manual_compaction_summary(monkeypatch, cleanup_test_sessions, summary_text):
    sid = _make_session()
    cleanup_test_sessions.append(sid)

    _install_fake_compression_runtime(monkeypatch, _FakeAgent)
    _install_manual_summary(monkeypatch, summary_text)

    payload = compress_session(sid)
    return payload["session"]["compression_anchor_summary"], get_session(sid)


def test_manual_and_streaming_compaction_preserve_long_summaries(
    monkeypatch, cleanup_test_sessions
):
    long_summary = ("Alpha summary line.\n" + "Long detail " * 40 + "tail").strip()

    route_summary, stored_session = _run_manual_compaction_summary(
        monkeypatch, cleanup_test_sessions, long_summary
    )

    assert route_summary == _compact_summary_text(long_summary)
    assert route_summary == stored_session.compression_anchor_summary
    assert route_summary is not None
    assert len(route_summary) > 320


def test_manual_and_streaming_compaction_normalize_blank_summaries(
    monkeypatch, cleanup_test_sessions
):
    blank_summary = " \n\t  "

    route_summary, stored_session = _run_manual_compaction_summary(
        monkeypatch, cleanup_test_sessions, blank_summary
    )

    assert route_summary is None
    assert route_summary == _compact_summary_text(blank_summary)
    assert stored_session.compression_anchor_summary is None
