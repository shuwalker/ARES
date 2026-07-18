"""Step 1 contracts for the parallel FastAPI application."""

import asyncio
from pathlib import Path

import httpx
import pytest
from fastapi import FastAPI

from fastapi_app.main import create_app


@pytest.fixture
def frontend_root(tmp_path: Path) -> Path:
    root = tmp_path / "dist"
    (root / "assets").mkdir(parents=True)
    (root / "index.html").write_text(
        "<!doctype html><div id='root'></div>"
        "<script>window.__ARES_CONFIG__=__ARES_RUNTIME_CONFIG_JSON__;</script>",
        encoding="utf-8",
    )
    (root / "assets" / "index-test.js").write_text(
        "window.ARES=true;",
        encoding="utf-8",
    )
    (root / "site.webmanifest").write_text(
        '{"name":"ARES"}',
        encoding="utf-8",
    )
    (root / "sw.js").write_text(
        "self.registration.unregister();",
        encoding="utf-8",
    )
    return root


def _app(root: Path, *, csrf_token: str = "") -> FastAPI:
    return create_app(
        frontend_root=root,
        csrf_resolver=lambda _request: csrf_token,
    )


def _get(app: FastAPI, path: str) -> httpx.Response:
    async def request() -> httpx.Response:
        transport = httpx.ASGITransport(app=app)
        async with httpx.AsyncClient(
            transport=transport,
            base_url="http://testserver",
        ) as client:
            return await client.get(path)

    return asyncio.run(request())


def test_root_serves_react_shell_with_runtime_config(frontend_root: Path):
    response = _get(_app(frontend_root, csrf_token="session-token"), "/")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/html")
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["x-ares-frontend"] == "react"
    assert "__ARES_RUNTIME_CONFIG_JSON__" not in response.text
    assert 'window.__ARES_CONFIG__={csrfToken:"session-token"}' in response.text


@pytest.mark.parametrize("path", ["/today", "/workspace", "/share/public-token"])
def test_non_file_navigation_uses_spa_shell(frontend_root: Path, path: str):
    response = _get(_app(frontend_root), path)

    assert response.status_code == 200
    assert response.headers["x-ares-frontend"] == "react"
    assert "<div id='root'></div>" in response.text


def test_runtime_config_escapes_script_breakout_text(frontend_root: Path):
    response = _get(_app(frontend_root, csrf_token="</script>"), "/")

    assert response.status_code == 200
    runtime_config = response.text.split("window.__ARES_CONFIG__=", 1)[1].split(
        ";</script>", 1
    )[0]
    assert "</script>" not in runtime_config
    assert "\\u003c/script>" in runtime_config


def test_hashed_asset_is_physical_and_immutable(frontend_root: Path):
    response = _get(_app(frontend_root), "/assets/index-test.js")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("application/javascript")
    assert response.headers["cache-control"] == "public, max-age=31536000, immutable"
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.text == "window.ARES=true;"


@pytest.mark.parametrize(
    "path",
    [
        "/manifest.json",
        "/manifest.webmanifest",
        "/session/manifest.json",
        "/session/manifest.webmanifest",
    ],
)
def test_manifest_compatibility_aliases(frontend_root: Path, path: str):
    response = _get(_app(frontend_root), path)

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("application/manifest+json")
    assert response.headers["cache-control"] == "no-store"
    assert response.json() == {"name": "ARES"}


@pytest.mark.parametrize(
    "path",
    ["/assets/missing.js", "/missing.css", "/static/ui.js", "/api/not-real"],
)
def test_file_and_api_misses_are_never_spa_html(frontend_root: Path, path: str):
    response = _get(_app(frontend_root), path)

    assert response.status_code == 404
    assert response.json() == {"error": "not found"}
    assert "<div id='root'></div>" not in response.text


def test_registered_api_route_wins_before_spa_fallback(frontend_root: Path):
    def install_api_routes(app: FastAPI) -> None:
        @app.get("/api/probe")
        async def probe():
            return {"source": "api"}

    app = create_app(
        frontend_root=frontend_root,
        install_api_routes=install_api_routes,
    )

    response = _get(app, "/api/probe")

    assert response.status_code == 200
    assert response.json() == {"source": "api"}


def test_public_share_route_is_registered_before_spa(frontend_root: Path, monkeypatch):
    monkeypatch.setattr(
        "api.shares.load_share",
        lambda token: {"title": "Shared", "messages": [], "message_count": 0}
        if token == "valid-token"
        else None,
    )
    app = _app(frontend_root)

    response = _get(app, "/api/share/valid-token")
    missing = _get(app, "/api/share/missing")

    assert response.status_code == 200
    assert response.json()["share"]["title"] == "Shared"
    assert response.headers["x-robots-tag"] == "noindex, nofollow"
    assert missing.status_code == 404


def test_missing_build_is_explicit_without_api_shadowing(tmp_path: Path):
    app = _app(tmp_path / "missing-dist")

    shell_response = _get(app, "/workspace")
    api_response = _get(app, "/api/not-real")

    assert shell_response.status_code == 404
    assert shell_response.json() == {"error": "React frontend build not found"}
    assert api_response.status_code == 404
    assert api_response.json() == {"error": "not found"}
