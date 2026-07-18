import json
import subprocess
import time
from pathlib import Path
from types import SimpleNamespace

import pytest

import api.models as models
from api.models import SESSIONS, Session, new_session


@pytest.fixture(autouse=True)
def _isolate_sessions(tmp_path, monkeypatch):
    session_dir = tmp_path / "sessions"
    session_dir.mkdir()
    monkeypatch.setattr(models, "SESSION_DIR", session_dir)
    monkeypatch.setattr(models, "SESSION_INDEX_FILE", session_dir / "_index.json")
    monkeypatch.setenv("GIT_CEILING_DIRECTORIES", str(tmp_path.parent.resolve()))
    SESSIONS.clear()
    yield session_dir
    SESSIONS.clear()


def test_worktree_metadata_round_trips_through_session_file(_isolate_sessions):
    s = Session(
        session_id="worktree001",
        workspace=str(_isolate_sessions.parent / "repo" / ".worktrees" / "ares-1234"),
        worktree_path=str(_isolate_sessions.parent / "repo" / ".worktrees" / "ares-1234"),
        worktree_branch="ares/ares-1234",
        worktree_repo_root=str(_isolate_sessions.parent / "repo"),
        worktree_created_at=123.5,
    )
    s.save()

    raw = json.loads(s.path.read_text(encoding="utf-8"))
    assert Path(raw["worktree_path"]).as_posix().endswith(".worktrees/ares-1234")
    assert raw["worktree_branch"] == "ares/ares-1234"
    assert raw["worktree_repo_root"].endswith("repo")
    assert raw["worktree_created_at"] == 123.5

    loaded = Session.load("worktree001")
    assert loaded.worktree_path == s.worktree_path
    assert loaded.worktree_branch == "ares/ares-1234"
    assert loaded.worktree_repo_root == s.worktree_repo_root
    assert loaded.worktree_created_at == 123.5
    assert loaded.compact()["worktree_branch"] == "ares/ares-1234"


def test_new_session_with_worktree_info_persists_immediately(_isolate_sessions):
    repo = _isolate_sessions.parent / "repo"
    worktree = repo / ".worktrees" / "ares-abcd1234"
    worktree.mkdir(parents=True)

    s = new_session(
        workspace=str(worktree),
        worktree_info={
            "path": str(worktree),
            "branch": "ares/ares-abcd1234",
            "repo_root": str(repo),
            "created_at": 456.0,
        },
    )

    assert s.path.exists(), (
        "worktree-backed sessions must be persisted at creation time so the "
        "real filesystem worktree is not orphaned by a browser/server restart"
    )
    assert s.worktree_path == str(worktree.resolve())
    assert s.worktree_branch == "ares/ares-abcd1234"
    assert s.worktree_repo_root == str(repo.resolve())
    assert s.worktree_created_at == 456.0


def test_empty_worktree_session_remains_visible_in_sidebar(_isolate_sessions):
    repo = _isolate_sessions.parent / "repo"
    worktree = repo / ".worktrees" / "ares-visible"
    worktree.mkdir(parents=True)

    s = new_session(
        workspace=str(worktree),
        worktree_info={
            "path": str(worktree),
            "branch": "ares/ares-visible",
            "repo_root": str(repo),
            "created_at": 789.0,
        },
    )

    ids = {row["session_id"] for row in models.all_sessions()}
    assert s.session_id in ids, (
        "worktree-backed sessions represent real filesystem state immediately "
        "and must survive the empty-session sidebar filter"
    )


def test_find_git_repo_root_uses_git_from_nested_workspace(tmp_path):
    from api.worktrees import find_git_repo_root

    repo = tmp_path / "repo"
    nested = repo / "apps" / "web"
    nested.mkdir(parents=True)
    subprocess.run(["git", "init"], cwd=repo, check=True, capture_output=True)

    assert find_git_repo_root(nested) == repo.resolve()


def test_find_git_repo_root_rejects_non_git_workspace(tmp_path):
    from api.worktrees import find_git_repo_root

    with pytest.raises(ValueError, match="not inside a git repository"):
        find_git_repo_root(tmp_path)


def test_create_worktree_for_workspace_calls_agent_setup_with_repo_root(tmp_path, monkeypatch):
    import api.worktrees as worktrees

    repo = tmp_path / "repo"
    nested = repo / "src"
    nested.mkdir(parents=True)
    subprocess.run(["git", "init"], cwd=repo, check=True, capture_output=True)
    seen = {}

    def fake_setup(repo_root):
        seen["repo_root"] = repo_root
        return {
            "path": str(repo / ".worktrees" / "ares-test"),
            "branch": "ares/ares-test",
            "repo_root": str(repo),
        }

    monkeypatch.setattr(worktrees, "_setup_agent_worktree", fake_setup)
    now = time.time()

    info = worktrees.create_worktree_for_workspace(nested)

    assert seen["repo_root"] == str(repo.resolve())
    assert Path(info["path"]).as_posix().endswith(".worktrees/ares-test")
    assert info["branch"] == "ares/ares-test"
    assert info["repo_root"] == str(repo.resolve())
    assert info["created_at"] >= now






def test_session_new_route_creates_worktree_backed_session(tmp_path, monkeypatch):
    from fastapi.testclient import TestClient
    from fastapi_app.main import create_app
    import api.worktrees as worktrees

    repo = tmp_path / "repo"
    worktree = repo / ".worktrees" / "ares-route"
    worktree.mkdir(parents=True)
    monkeypatch.setattr("api.workspace.resolve_trusted_workspace", lambda raw: Path(raw).resolve())
    monkeypatch.setattr(
        worktrees,
        "create_worktree_for_workspace",
        lambda workspace: {
            "path": str(worktree),
            "branch": "ares/ares-route",
            "repo_root": str(repo),
            "created_at": 321.0,
        },
    )
    with TestClient(create_app()) as client:
        response = client.post(
            "/api/session/new",
            json={"workspace": str(repo), "worktree": True, "profile": "default"},
        )

    assert response.status_code == 200
    session = response.json()["session"]
    assert session["workspace"] == str(worktree.resolve())
    assert session["worktree_path"] == str(worktree.resolve())
    assert session["worktree_branch"] == "ares/ares-route"


def test_session_new_worktree_fallback_workspace_is_resolved(tmp_path, monkeypatch):
    from fastapi.testclient import TestClient
    from fastapi_app.main import create_app
    import api.worktrees as worktrees

    repo = tmp_path / "repo"
    worktree = repo / ".worktrees" / "ares-route"
    worktree.mkdir(parents=True)
    seen = []
    monkeypatch.setattr("api.workspace.get_last_workspace", lambda: str(repo))
    monkeypatch.setattr("api.workspace.resolve_trusted_workspace", lambda raw: Path(raw).resolve())
    monkeypatch.setattr(
        worktrees,
        "create_worktree_for_workspace",
        lambda workspace: seen.append(workspace) or {
            "path": str(worktree),
            "branch": "ares/ares-route",
            "repo_root": str(repo),
            "created_at": 321.0,
        },
    )
    with TestClient(create_app()) as client:
        response = client.post(
            "/api/session/new",
            json={"worktree": True, "profile": "default"},
        )

    assert response.status_code == 200
    assert seen == [str(repo.resolve())]
    assert response.json()["session"]["workspace"] == str(worktree.resolve())
