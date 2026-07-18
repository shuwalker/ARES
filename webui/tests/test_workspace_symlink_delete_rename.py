"""Symlink guards on the modular FastAPI workspace file endpoints."""

from __future__ import annotations

import os
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from fastapi_app.main import create_app


@pytest.fixture()
def workspace(tmp_path):
    root = tmp_path / "workspace"
    root.mkdir()
    return root


def _post(monkeypatch, workspace, endpoint, payload):
    monkeypatch.setattr(
        "api.models.get_session_for_file_ops",
        lambda _session_id: SimpleNamespace(workspace=str(workspace), profile="default"),
    )
    with TestClient(create_app()) as client:
        return client.post(endpoint, json={"session_id": "session-1", **payload})


def _symlink(target, link):
    try:
        os.symlink(str(target), str(link))
    except (OSError, NotImplementedError):
        pytest.skip("platform does not support symlinks")


@pytest.mark.parametrize(
    ("endpoint", "payload", "verb"),
    [
        ("/api/file/delete", {"path": "link", "recursive": True}, "delete"),
        ("/api/file/rename", {"path": "link", "new_name": "renamed"}, "rename"),
        ("/api/file/save", {"path": "link", "content": "changed"}, "save"),
    ],
)
def test_file_mutations_reject_symlinked_files(monkeypatch, workspace, endpoint, payload, verb):
    target = workspace / "target.txt"
    target.write_text("important", encoding="utf-8")
    _symlink(target, workspace / "link")

    response = _post(monkeypatch, workspace, endpoint, payload)

    assert response.status_code == 400
    assert f"Cannot {verb}" in response.json()["error"]
    assert target.read_text(encoding="utf-8") == "important"


@pytest.mark.parametrize(
    ("endpoint", "payload", "verb"),
    [
        ("/api/file/delete", {"path": "link", "recursive": True}, "delete"),
        ("/api/file/rename", {"path": "link", "new_name": "renamed"}, "rename"),
    ],
)
def test_file_mutations_reject_symlinked_directories(monkeypatch, workspace, endpoint, payload, verb):
    target = workspace / "target"
    target.mkdir()
    _symlink(target, workspace / "link")

    response = _post(monkeypatch, workspace, endpoint, payload)

    assert response.status_code == 400
    assert f"Cannot {verb}" in response.json()["error"]
    assert target.exists()


@pytest.mark.parametrize(
    ("endpoint", "payload", "verb"),
    [
        ("/api/file/delete", {"path": "dangling", "recursive": True}, "delete"),
        ("/api/file/rename", {"path": "dangling", "new_name": "renamed"}, "rename"),
        ("/api/file/save", {"path": "dangling", "content": "changed"}, "save"),
    ],
)
def test_dangling_symlinks_are_rejected_before_missing_file_checks(
    monkeypatch, workspace, endpoint, payload, verb
):
    _symlink(workspace / "missing-target", workspace / "dangling")

    response = _post(monkeypatch, workspace, endpoint, payload)

    assert response.status_code == 400
    assert f"Cannot {verb}" in response.json()["error"]


def test_real_directory_delete_still_works(monkeypatch, workspace):
    target = workspace / "delete-me"
    target.mkdir()
    (target / "child.txt").write_text("x", encoding="utf-8")

    response = _post(
        monkeypatch,
        workspace,
        "/api/file/delete",
        {"path": "delete-me", "recursive": True},
    )

    assert response.status_code == 200
    assert response.json()["ok"] is True
    assert not target.exists()


def test_real_file_rename_and_save_still_work(monkeypatch, workspace):
    target = workspace / "old.txt"
    target.write_text("old", encoding="utf-8")

    renamed = _post(
        monkeypatch,
        workspace,
        "/api/file/rename",
        {"path": "old.txt", "new_name": "new.txt"},
    )
    saved = _post(
        monkeypatch,
        workspace,
        "/api/file/save",
        {"path": "new.txt", "content": "new"},
    )

    assert renamed.status_code == 200
    assert saved.status_code == 200
    assert (workspace / "new.txt").read_text(encoding="utf-8") == "new"


def test_move_workspace_symlink_is_rejected(monkeypatch, workspace):
    target = workspace / "target.txt"
    target.write_text("data", encoding="utf-8")
    (workspace / "dest").mkdir()
    _symlink(target, workspace / "link.txt")

    response = _post(
        monkeypatch,
        workspace,
        "/api/file/move",
        {"path": "link.txt", "dest_dir": "dest"},
    )

    assert response.status_code == 400
    assert "Cannot move a symlinked entry" in response.json()["error"]
