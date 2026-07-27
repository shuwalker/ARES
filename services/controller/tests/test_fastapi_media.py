"""FastAPI media delivery preserves workspace and state-file boundaries."""

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from fastapi_app.main import create_app
from fastapi_app.request_context import RequestIdentity, require_identity


IDENTITY = RequestIdentity(session_cookie=None, profile="default", auth_enabled=False)


@pytest.fixture
def media_client(monkeypatch, tmp_path: Path):
    ares_home = tmp_path / ".ares"
    workspace = ares_home / "workspace"
    workspace.mkdir(parents=True)
    import api.profiles as profiles
    import api.workspace as workspace_api

    monkeypatch.setattr(profiles, "get_active_ares_home", lambda: ares_home)
    monkeypatch.setattr(profiles, "_DEFAULT_ARES_HOME", ares_home)
    monkeypatch.setattr(workspace_api, "get_last_workspace", lambda: str(workspace))
    app = create_app()
    app.dependency_overrides[require_identity] = lambda: IDENTITY
    with TestClient(app) as client:
        yield client, ares_home, workspace


def test_workspace_image_is_inline_by_default(media_client):
    client, _ares_home, workspace = media_client
    image = workspace / "capture.png"
    image.write_bytes(b"png")
    response = client.get("/api/media", params={"path": str(image)})
    assert response.status_code == 200
    assert response.content == b"png"
    assert response.headers["content-type"] == "image/png"
    assert response.headers["content-disposition"].startswith("inline")


def test_state_secrets_remain_denied(media_client):
    client, ares_home, _workspace = media_client
    secret = ares_home / ".env"
    secret.write_text("TOKEN=secret")
    response = client.get("/api/media", params={"path": str(secret)})
    assert response.status_code == 403
    assert response.json()["error"] == "Path not in allowed location"


def test_state_subdirectories_are_denied_even_if_workspace_overlaps(media_client, monkeypatch):
    client, ares_home, _workspace = media_client
    session_file = ares_home / "sessions" / "session.json"
    session_file.parent.mkdir()
    session_file.write_text("secret")
    import api.workspace as workspace_api

    monkeypatch.setattr(workspace_api, "get_last_workspace", lambda: str(ares_home))
    response = client.get("/api/media", params={"path": str(session_file)})
    assert response.status_code == 403


def test_svg_is_always_an_attachment(media_client):
    client, _ares_home, workspace = media_client
    svg = workspace / "drawing.svg"
    svg.write_text("<svg/>")
    response = client.get("/api/media", params={"path": str(svg), "inline": "1"})
    assert response.status_code == 200
    assert response.headers["content-disposition"].startswith("attachment")


def test_html_inline_preview_is_sandboxed(media_client):
    client, _ares_home, workspace = media_client
    html = workspace / "report.html"
    html.write_text("<!doctype html><h1>Report</h1>")
    response = client.get("/api/media", params={"path": str(html), "inline": "1"})
    assert response.status_code == 200
    assert response.headers["content-security-policy"] == "sandbox allow-scripts"
    assert '<base target="_blank">' in response.text


def test_path_outside_allowed_roots_is_forbidden(media_client, tmp_path):
    client, _ares_home, _workspace = media_client
    outside = tmp_path.parent / "outside-ares-media.txt"
    outside.write_text("private")
    try:
        response = client.get("/api/media", params={"path": str(outside)})
        assert response.status_code == 403
    finally:
        outside.unlink(missing_ok=True)
