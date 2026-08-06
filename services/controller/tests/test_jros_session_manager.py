"""Tests for integrations.workers.jros_session_manager.

Uses a tiny fake bridge process (a stdlib-only Python one-liner) that speaks
just enough of the real v1 NDJSON protocol to exercise session persistence,
crash-and-restart, and shutdown — no real JaegerAI install required.

The fake bridge replies with its own PID instead of echoing the sent text.
That is the whole test strategy: if two calls for the same session_id come
back with the SAME pid, the manager reused one persistent process (the
actual bug this module fixes — see integrations/workers/jaeger_worker.py's
_execute_bridge docstring); a DIFFERENT session_id must get a DIFFERENT pid;
and a deliberately crashed process must be replaced by a fresh (differently
PID'd) one automatically, exactly once.
"""
from __future__ import annotations

import sys

import pytest

from integrations.providers.jaeger.bridge_client import JrosError
from integrations.workers import jros_session_manager as manager

_FAKE_BRIDGE_SCRIPT = """
import sys, os, json

print(json.dumps({"type": "ready", "instance": "test", "model": "fake"}), flush=True)
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        frame = json.loads(line)
    except Exception:
        continue
    if frame.get("op") == "quit":
        break
    if frame.get("op") == "send":
        if frame.get("text") == "CRASH":
            sys.exit(1)
        print(json.dumps({"type": "reply", "text": str(os.getpid())}), flush=True)
sys.exit(0)
"""

_FAKE_COMMAND = [sys.executable, "-c", _FAKE_BRIDGE_SCRIPT]


@pytest.fixture(autouse=True)
def _clean_sessions():
    """Every test gets a clean manager; leaked fake processes are killed."""
    manager.close_all()
    yield
    manager.close_all()


def test_run_turn_starts_a_process_and_returns_its_reply():
    result = manager.run_turn("session-a", "hello", command=_FAKE_COMMAND)
    assert result["error"] is None
    assert result["text"].isdigit()  # the fake bridge's own pid


def test_same_session_id_reuses_the_same_process():
    first = manager.run_turn("session-b", "turn one", command=_FAKE_COMMAND)
    second = manager.run_turn("session-b", "turn two", command=_FAKE_COMMAND)
    assert first["text"] == second["text"], (
        "two turns on the same session_id must hit the same persistent "
        "bridge process, not boot a fresh one per call"
    )


def test_different_session_ids_get_different_processes():
    a = manager.run_turn("session-c1", "hi", command=_FAKE_COMMAND)
    b = manager.run_turn("session-c2", "hi", command=_FAKE_COMMAND)
    assert a["text"] != b["text"]


def test_crashed_process_is_replaced_once_and_call_still_succeeds(tmp_path):
    # A command that crashes on its very first launch only (a marker file
    # records that the first process ever ran), then behaves normally on
    # any later launch — models a real bridge that crashed once and came
    # back healthy, independent of what message triggered the crash.
    # Retrying the exact same message against the exact same fake command
    # deliberately proves the manager spawned a genuinely NEW process
    # rather than reusing the dead one.
    marker = tmp_path / "launched-once"
    script = f"""
import sys, os, json
MARKER = {str(marker)!r}
print(json.dumps({{"type": "ready", "instance": "test", "model": "fake"}}), flush=True)
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        frame = json.loads(line)
    except Exception:
        continue
    if frame.get("op") == "quit":
        break
    if frame.get("op") == "send":
        if not os.path.exists(MARKER):
            open(MARKER, "w").close()
            sys.exit(1)
        print(json.dumps({{"type": "reply", "text": str(os.getpid())}}), flush=True)
sys.exit(0)
"""
    crash_once_command = [sys.executable, "-c", script]

    result = manager.run_turn("session-d", "hello", command=crash_once_command)
    assert result["error"] is None
    assert result["text"].isdigit(), (
        "the first process crashes without ever replying; the manager "
        "must transparently retry with a fresh process and return that "
        "process's real reply, not surface the crash to the caller"
    )


def test_close_session_removes_it_from_the_live_set():
    manager.run_turn("session-e", "hello", command=_FAKE_COMMAND)
    assert "session-e" in manager._clients
    manager.close_session("session-e")
    assert "session-e" not in manager._clients


def test_close_all_clears_every_session():
    manager.run_turn("session-f1", "hi", command=_FAKE_COMMAND)
    manager.run_turn("session-f2", "hi", command=_FAKE_COMMAND)
    assert len(manager._clients) == 2
    manager.close_all()
    assert manager._clients == {}


def test_no_command_and_no_real_install_raises_honest_jros_error(tmp_path, monkeypatch):
    """Without a command override, JrosClient resolves a real install path;
    on a machine with no JaegerAI installed at that path it must raise
    JrosError, never silently return empty text (CLAUDE.md: no silent
    failure — a missing worker must be a reported error)."""
    fake_home = tmp_path / "no-jaeger-here"
    with pytest.raises(JrosError):
        manager.run_turn("session-g", "hello", jaeger_home=str(fake_home))
