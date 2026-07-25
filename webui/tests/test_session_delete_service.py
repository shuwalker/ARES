"""Destructive session deletion service contract."""

from __future__ import annotations

from pathlib import Path
import threading
from types import SimpleNamespace


def test_delete_session_removes_sidecar_journals_state_and_runtime_handles(tmp_path, monkeypatch):
    from api.session_mutations import delete_session

    session_id = "delete-service-1"
    session_dir = tmp_path / "sessions"
    session_dir.mkdir()
    sidecar = session_dir / f"{session_id}.json"
    backup = session_dir / f"{session_id}.json.bak"
    sidecar.write_text("{}", encoding="utf-8")
    backup.write_text("{}", encoding="utf-8")
    session = SimpleNamespace(session_id=session_id, profile="default", worktree_path="/tmp/worktree")
    calls: list[tuple[str, str]] = []

    monkeypatch.setattr("api.config.SESSION_DIR", session_dir)
    monkeypatch.setattr("api.config.SESSIONS", {session_id: session})
    monkeypatch.setattr("api.config.SESSION_AGENT_LOCKS", {session_id: threading.Lock()})
    monkeypatch.setattr("api.config._evict_session_agent", lambda sid: calls.append(("evict", sid)))
    monkeypatch.setattr("api.models.Session.load", lambda sid: session)
    monkeypatch.setattr("api.models.get_session", lambda sid, metadata_only=False: session)
    monkeypatch.setattr("api.models.prune_session_from_index", lambda sid: calls.append(("index", sid)))
    monkeypatch.setattr(
        "api.models._record_webui_deleted_session_tombstone",
        lambda sid: calls.append(("tombstone", sid)),
    )
    monkeypatch.setattr("api.models.delete_cli_session", lambda sid: calls.append(("state_db", sid)))
    monkeypatch.setattr("api.session_access.lookup_cli_session_metadata", lambda sid: {})
    monkeypatch.setattr("api.session_access.session_is_subagent_view_only", lambda sid: False)
    monkeypatch.setattr("api.session_access.is_messaging_session_record", lambda value: False)
    monkeypatch.setattr("api.turn_journal.delete_turn_journal", lambda sid: calls.append(("turn", sid)))
    monkeypatch.setattr("api.run_journal.delete_run_journal", lambda sid: calls.append(("run", sid)))
    monkeypatch.setattr(
        "api.background_process.forget_bg_task_completion_dedup",
        lambda sid: calls.append(("dedup", sid)),
    )
    monkeypatch.setattr("api.terminal.close_terminal", lambda sid: calls.append(("terminal", sid)))
    monkeypatch.setattr(
        "api.session_events.publish_session_list_changed",
        lambda reason, **kwargs: calls.append((reason, kwargs.get("profile") or "")),
    )
    monkeypatch.setattr("api.upload._session_attachment_dir", lambda sid: Path(tmp_path / "attachments" / sid))

    result = delete_session(session_id)

    assert result == {"ok": True, "worktree_retained": True, "worktree_path": "/tmp/worktree"}
    assert not sidecar.exists()
    assert not backup.exists()
    assert {name for name, _value in calls} >= {
        "evict",
        "index",
        "tombstone",
        "state_db",
        "turn",
        "run",
        "dedup",
        "terminal",
        "session_delete",
    }
