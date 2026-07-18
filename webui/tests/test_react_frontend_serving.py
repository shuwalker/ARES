"""Serving contracts for the React-only FastAPI frontend."""

from __future__ import annotations

from fastapi.testclient import TestClient
import pytest

from fastapi_app.main import create_app


@pytest.fixture()
def frontend_root(tmp_path):
    (tmp_path / "assets").mkdir()
    (tmp_path / "index.html").write_text(
        "<!doctype html><script>window.__ARES_CONFIG__=__ARES_RUNTIME_CONFIG_JSON__;</script>ARES React test",
        encoding="utf-8",
    )
    (tmp_path / "login.js").write_text("login();", encoding="utf-8")
    (tmp_path / "site.webmanifest").write_text('{"name":"ARES"}', encoding="utf-8")
    (tmp_path / "sw.js").write_text("self.registration.unregister();", encoding="utf-8")
    (tmp_path / "assets" / "index-abc123.js").write_text("react();", encoding="utf-8")
    return tmp_path


@pytest.fixture()
def client(frontend_root):
    with TestClient(create_app(frontend_root=frontend_root)) as value:
        yield value


@pytest.mark.parametrize("path", ["/", "/today", "/share/public-token"])
def test_navigation_serves_react_spa_shell(client, path):
    response = client.get(path)
    assert response.status_code == 200
    assert response.headers["x-ares-frontend"] == "react"
    assert "ARES React test" in response.text
    assert "__ARES_RUNTIME_CONFIG_JSON__" not in response.text
    assert 'window.__ARES_CONFIG__={csrfToken:""}' in response.text


def test_support_assets_and_manifest_come_from_build(client):
    assert client.get("/login.js").text == "login();"
    manifest = client.get("/manifest.json")
    assert manifest.status_code == 200
    assert manifest.headers["content-type"].startswith("application/manifest+json")
    assert manifest.json() == {"name": "ARES"}
    assert "registration.unregister" in client.get("/sw.js").text


def test_hashed_asset_is_immutable(client):
    response = client.get("/assets/index-abc123.js")
    assert response.status_code == 200
    assert response.headers["cache-control"] == "public, max-age=31536000, immutable"
    assert response.headers["content-type"].startswith("application/javascript")


@pytest.mark.parametrize("path", ["/fonts/missing.woff2", "/missing.js", "/static/ui.js"])
def test_missing_or_retired_assets_are_json_404_not_spa(client, path):
    response = client.get(path)
    assert response.status_code == 404
    assert response.json() == {"error": "not found"}


def test_missing_build_returns_explicit_404(tmp_path):
    with TestClient(create_app(frontend_root=tmp_path / "missing")) as client:
        response = client.get("/workspace")
    assert response.status_code == 404
    assert response.json()["error"] == "React frontend build not found"


def test_unknown_api_is_never_swallowed_or_shadowed(client, frontend_root):
    shadow = frontend_root / "api" / "not-real.json"
    shadow.parent.mkdir()
    shadow.write_text('{"wrong":"frontend"}', encoding="utf-8")
    for path in ("/api/not-a-real-endpoint", "/api/not-real.json"):
        response = client.get(path)
        assert response.status_code == 404
        assert response.json() == {"error": "not found"}


class _ViteResponse:
    status = 200

    def read(self):
        return b"vite response"

    def getheaders(self):
        return [("Content-Type", "text/html; charset=utf-8"), ("Connection", "keep-alive")]


class _ViteConnection:
    last_target = None

    def __init__(self, host, port, timeout):
        assert (host, port, timeout) == ("127.0.0.1", 5173, 3)

    def request(self, method, target, headers):
        assert method == "GET"
        self.__class__.last_target = target

    def getresponse(self):
        return _ViteResponse()

    def close(self):
        pass


def test_vite_proxy_requires_flag_and_never_receives_api(client, monkeypatch):
    from fastapi_app import vite_proxy

    monkeypatch.setenv("ARES_VITE_DEV", "1")
    monkeypatch.setattr(vite_proxy.http.client, "HTTPConnection", _ViteConnection)
    response = client.get("/today?view=compact")
    assert response.status_code == 200
    assert response.headers["x-ares-frontend"] == "vite-dev"
    assert "connection" not in response.headers
    assert response.text == "vite response"
    assert _ViteConnection.last_target == "/today?view=compact"
    assert client.get("/api/not-real").status_code == 404


def test_unavailable_vite_falls_back_to_compiled_build(client, monkeypatch):
    from fastapi_app import vite_proxy

    class Offline:
        def __init__(self, *args, **kwargs):
            pass

        def request(self, *args, **kwargs):
            raise ConnectionRefusedError("offline")

        def close(self):
            pass

    monkeypatch.setenv("ARES_VITE_DEV", "yes")
    monkeypatch.setattr(vite_proxy.http.client, "HTTPConnection", Offline)
    response = client.get("/today")
    assert response.status_code == 200
    assert response.headers["x-ares-frontend"] == "react"
