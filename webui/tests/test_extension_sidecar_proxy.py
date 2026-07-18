"""FastAPI contract tests for the authenticated extension sidecar proxy."""

from __future__ import annotations

from email.message import Message
from io import BytesIO
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from api.extension_proxy import (
    _EXTENSION_SIDECAR_PROXY_MAX_RESPONSE_BYTES,
    _extension_sidecar_proxy_redirect_url,
    _forward_headers,
)
from fastapi_app.main import create_app


class _Upstream:
    status = 200

    def __init__(self, body=b'{"ok":true}', headers=None):
        self._body = BytesIO(body)
        self.headers = headers or Message()

    def read(self, size=-1):
        return self._body.read(size)

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


class _Opener:
    def __init__(self, response):
        self.response = response
        self.request = None

    def open(self, request, timeout):
        self.request = request
        assert timeout == 10
        return self.response


@pytest.fixture(autouse=True)
def no_auth(monkeypatch):
    import api.auth

    monkeypatch.setattr(api.auth, "is_auth_enabled", lambda: False)


@pytest.fixture
def client(tmp_path: Path):
    dist = tmp_path / "dist"
    dist.mkdir()
    (dist / "index.html").write_text("<div id='root'></div>", encoding="utf-8")
    with TestClient(create_app(frontend_root=dist), client=("127.0.0.1", 50000)) as value:
        yield value


def _allow_target(monkeypatch):
    import api.extensions

    monkeypatch.setattr(
        api.extensions,
        "resolve_extension_sidecar_proxy_target",
        lambda extension_id, proxy_path, query="": {
            "origin": "http://127.0.0.1:17787",
            "upstream_url": f"http://127.0.0.1:17787/{proxy_path}?{query}".rstrip("?"),
        },
    )


def test_proxy_forwards_through_fastapi_and_strips_ambient_credentials(client, monkeypatch):
    import api.extension_proxy as proxy

    _allow_target(monkeypatch)
    headers = Message()
    headers["Content-Type"] = "application/json"
    headers["Set-Cookie"] = "sidecar-secret=1"
    opener = _Opener(_Upstream(headers=headers))
    monkeypatch.setattr(proxy, "_extension_sidecar_proxy_same_origin_opener", lambda _origin: opener)

    response = client.post(
        "/api/extensions/demo/sidecar/v1/run?mode=fast",
        content=b"payload",
        headers={
            "origin": "http://testserver",
            "sec-fetch-site": "same-origin",
            "authorization": "Bearer browser-secret",
            "cookie": "session=browser-secret",
            "x-csrf-token": "csrf-secret",
            "x-extension-input": "safe",
        },
    )

    assert response.status_code == 200
    assert response.json() == {"ok": True}
    forwarded = {key.lower(): value for key, value in opener.request.header_items()}
    assert forwarded["x-extension-input"] == "safe"
    assert "authorization" not in forwarded
    assert "cookie" not in forwarded
    assert "x-csrf-token" not in forwarded
    assert "set-cookie" not in response.headers
    assert response.headers["cache-control"] == "no-store"


def test_proxy_root_route_and_same_origin_navigation_are_supported(client, monkeypatch):
    import api.extension_proxy as proxy

    _allow_target(monkeypatch)
    monkeypatch.setattr(
        proxy,
        "_extension_sidecar_proxy_same_origin_opener",
        lambda _origin: _Opener(_Upstream()),
    )
    response = client.get(
        "/api/extensions/demo/sidecar",
        headers={"sec-fetch-site": "none"},
    )
    assert response.status_code == 200


@pytest.mark.parametrize(
    "headers",
    [
        {"sec-fetch-site": "cross-site", "origin": "https://attacker.invalid"},
        {"sec-fetch-site": "same-origin"},
        {"origin": "https://attacker.invalid"},
    ],
)
def test_proxy_fails_closed_without_same_origin_browser_provenance(client, headers):
    response = client.get("/api/extensions/demo/sidecar/status", headers=headers)
    assert response.status_code == 403


def test_proxy_bounds_upstream_response(client, monkeypatch):
    import api.extension_proxy as proxy

    _allow_target(monkeypatch)
    oversized = b"x" * (_EXTENSION_SIDECAR_PROXY_MAX_RESPONSE_BYTES + 1)
    monkeypatch.setattr(
        proxy,
        "_extension_sidecar_proxy_same_origin_opener",
        lambda _origin: _Opener(_Upstream(oversized)),
    )
    response = client.get(
        "/api/extensions/demo/sidecar/status",
        headers={"origin": "http://testserver", "sec-fetch-site": "same-origin"},
    )
    assert response.status_code == 502
    assert response.json()["error"] == "Extension sidecar response too large"


def test_redirects_must_remain_on_declared_origin():
    origin = "http://127.0.0.1:17787"
    current = f"{origin}/v1/start"
    assert _extension_sidecar_proxy_redirect_url(origin, current, "/v1/next") == f"{origin}/v1/next"
    assert _extension_sidecar_proxy_redirect_url(origin, current, "http://127.0.0.1:17788/x") is None
    assert _extension_sidecar_proxy_redirect_url(origin, current, "https://127.0.0.1:17787/x") is None
    assert _extension_sidecar_proxy_redirect_url(origin, current, "http://attacker.invalid/x") is None


def test_header_filter_removes_hop_by_hop_and_connection_named_headers():
    filtered = _forward_headers(
        {
            "Connection": "X-Private, keep-alive",
            "X-Private": "secret",
            "Transfer-Encoding": "chunked",
            "X-Safe": "yes",
        }
    )
    assert filtered == {"X-Safe": "yes"}
