import sqlite3
from pathlib import Path
import pytest
from fastapi.testclient import TestClient

import api.models as models
from api.models import SESSIONS, Session
from fastapi_app.main import create_app


def _post(path, body):
    with TestClient(create_app()) as client:
        return client.post(path, json=body)


def _isolate_session_store(tmp_path, monkeypatch):
    import api.config as config

    session_dir = tmp_path / "sessions"
    session_dir.mkdir()
    monkeypatch.setattr(models, "SESSION_DIR", session_dir)
    monkeypatch.setattr(models, "SESSION_INDEX_FILE", session_dir / "_index.json")
    monkeypatch.setattr(config, "SESSION_DIR", session_dir)
    SESSIONS.clear()
    return session_dir


def _worktree_session(tmp_path, session_id):
    repo = tmp_path / "repo"
    worktree = repo / ".worktrees" / f"ares-{session_id}"
    worktree.mkdir(parents=True)
    s = Session(
        session_id=session_id,
        title="Worktree session",
        workspace=str(worktree),
        worktree_path=str(worktree),
        worktree_branch=f"ares/{session_id}",
        worktree_repo_root=str(repo),
    )
    s.save()
    return s, worktree


def _make_state_db(path, sid, *, source="telegram"):
    conn = sqlite3.connect(str(path))
    conn.executescript(
        """
        CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            source TEXT,
            model TEXT,
            message_count INTEGER DEFAULT 0,
            started_at REAL,
            title TEXT,
            cwd TEXT
        );
        CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT,
            role TEXT,
            content TEXT,
            timestamp REAL
        );
        """
    )
    conn.execute(
        "INSERT INTO sessions (id, source, model, message_count, started_at, title, cwd) "
        "VALUES (?, ?, 'MiniMax-M3', 2, 1781024055.0, 'Telegram chat', ?)",
        (sid, source, str(path.parent)),
    )
    conn.execute(
        "INSERT INTO messages (session_id, role, content, timestamp) VALUES (?, 'user', 'hi', 1781024055.0)",
        (sid,),
    )
    conn.execute(
        "INSERT INTO messages (session_id, role, content, timestamp) VALUES (?, 'assistant', 'hello', 1781024056.0)",
        (sid,),
    )
    conn.commit()
    conn.close()


def test_delete_worktree_session_reports_retained_worktree_without_cleanup(tmp_path, monkeypatch):
    session_dir = _isolate_session_store(tmp_path, monkeypatch)
    session, worktree = _worktree_session(tmp_path, "wtdelete1")
    monkeypatch.setattr("api.session_access.lookup_cli_session_metadata", lambda sid, **kwargs: {})
    monkeypatch.setattr(models, "delete_cli_session", lambda sid: None)

    response = _post("/api/session/delete", {"session_id": session.session_id})

    assert response.status_code == 200
    assert response.json()["ok"] is True
    assert response.json()["worktree_retained"] is True
    assert response.json()["worktree_path"] == str(worktree.resolve())
    assert response.json()["worktree_branch"] == "ares/wtdelete1"
    assert not (session_dir / "wtdelete1.json").exists()
    assert worktree.exists(), "session delete must not remove the git worktree directory"


def test_delete_session_records_tombstone_when_state_db_delete_fails(tmp_path, monkeypatch):
    session_dir = _isolate_session_store(tmp_path, monkeypatch)
    sid = "dbfaildelete1"
    session = Session(
        session_id=sid,
        title="Delete failure",
        messages=[{"role": "user", "content": "keep deleted"}],
    )
    session.save()
    (session_dir / f"{sid}.json.bak").write_text("backup", encoding="utf-8")
    monkeypatch.setattr("api.session_access.lookup_cli_session_metadata", lambda sid, **kwargs: {})

    def fail_delete(value):
        raise RuntimeError("state.db locked")

    real_unlink = Path.unlink

    def fail_backup_unlink(path, *args, **kwargs):
        if path.name == f"{sid}.json.bak":
            raise PermissionError("backup locked")
        return real_unlink(path, *args, **kwargs)

    monkeypatch.setattr(models, "delete_cli_session", fail_delete)
    monkeypatch.setattr(Path, "unlink", fail_backup_unlink)

    response = _post("/api/session/delete", {"session_id": sid})

    assert response.status_code == 200
    assert response.json()["ok"] is True
    assert not (session_dir / f"{sid}.json").exists()
    assert sid in models._load_webui_deleted_session_tombstone()


def test_delete_messaging_session_preserves_foreign_state_and_blocks_mutation(
    tmp_path, monkeypatch
):
    session_dir = _isolate_session_store(tmp_path, monkeypatch)
    sid = "telegramdelete1"
    state_db = tmp_path / "state.db"
    _make_state_db(state_db, sid)
    monkeypatch.setattr(models, "_active_state_db_path", lambda: state_db)
    session = Session(session_id=sid, title="Telegram chat")
    session.save()
    cli_meta = {
        "session_id": sid,
        "source_tag": "telegram",
        "raw_source": "telegram",
        "session_source": "messaging",
    }
    monkeypatch.setattr("api.session_access.lookup_cli_session_metadata", lambda value, **kwargs: cli_meta)
    delete_calls = []
    monkeypatch.setattr(models, "delete_cli_session", lambda value: delete_calls.append(value))

    response = _post("/api/session/delete", {"session_id": sid})
    from api.session_access import get_or_materialize_session

    with pytest.raises(PermissionError, match="read-only imported session"):
        get_or_materialize_session(sid)

    assert response.status_code == 200
    assert response.json()["ok"] is True
    assert not (session_dir / f"{sid}.json").exists()
    assert sid not in models._load_webui_deleted_session_tombstone()
    assert delete_calls == []


def test_archive_worktree_session_reports_retained_worktree_without_cleanup(tmp_path, monkeypatch):
    _isolate_session_store(tmp_path, monkeypatch)
    session, worktree = _worktree_session(tmp_path, "wtarchive1")
    response = _post(
        "/api/session/archive",
        {"session_id": session.session_id, "archived": True},
    )

    assert response.status_code == 200
    assert response.json()["ok"] is True
    assert response.json()["session"]["archived"] is True
    assert response.json()["worktree_retained"] is True
    assert response.json()["worktree_path"] == str(worktree.resolve())
    assert worktree.exists(), "session archive must not remove the git worktree directory"
    assert Session.load("wtarchive1").archived is True
