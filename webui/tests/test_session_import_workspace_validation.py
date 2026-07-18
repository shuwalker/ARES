"""Imported sessions cannot expand workspace file access."""

from __future__ import annotations

from pathlib import Path

from fastapi.testclient import TestClient

from api.config import DEFAULT_WORKSPACE
from api.models import get_session
from api.workspace import resolve_trusted_workspace
from fastapi_app.main import create_app
from fastapi_app.request_context import RequestIdentity, require_mutation_identity


def _client():
    app = create_app()
    app.dependency_overrides[require_mutation_identity] = lambda: RequestIdentity(None, None, False)
    return TestClient(app)


def _import(client, workspace):
    return client.post(
        "/api/session/import",
        json={"title": "import", "workspace": workspace, "model": "test", "messages": []},
    )


def test_session_import_rejects_blocked_root_workspace():
    with _client() as client:
        response = _import(client, "/")
    assert response.status_code == 400
    assert "system directory" in response.json()["error"]


def test_session_import_rejects_non_path_workspace_value():
    with _client() as client:
        response = _import(client, {"not": "a path"})
    assert response.status_code in {400, 422}
    assert response.json()["error"]


def test_imported_session_file_read_stays_under_validated_workspace():
    workspace = Path(DEFAULT_WORKSPACE)
    workspace.mkdir(parents=True, exist_ok=True)
    (workspace / "allowed.txt").write_text("allowed", encoding="utf-8")
    with _client() as client:
        imported = _import(client, str(workspace))
        assert imported.status_code == 200
        session_id = imported.json()["session"]["session_id"]
        assert get_session(session_id).workspace == str(resolve_trusted_workspace(workspace))
        response = client.get(
            "/api/file",
            params={"session_id": session_id, "path": "allowed.txt"},
        )
    assert response.status_code == 200
    assert response.json()["content"] == "allowed"


def test_resolver_rejects_root_before_file_read():
    try:
        resolve_trusted_workspace(Path("/"))
    except ValueError as exc:
        assert "system directory" in str(exc)
    else:
        raise AssertionError("root workspace unexpectedly accepted")
