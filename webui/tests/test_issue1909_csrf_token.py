"""Session-bound CSRF behavior at the FastAPI request boundary."""

from __future__ import annotations

import hmac
import time

from fastapi.testclient import TestClient

import api.auth as auth
from fastapi_app.main import create_app


def _signed_cookie(raw_token: str) -> str:
    signature = hmac.new(auth._signing_key(), raw_token.encode(), "sha256").hexdigest()
    auth._sessions[raw_token] = time.time() + 60
    return f"{raw_token}.{signature}"


def _client(cookie: str, *, frontend_root=None):
    client = TestClient(create_app(frontend_root=frontend_root))
    client.cookies.set(auth.COOKIE_NAME, cookie)
    return client


def test_csrf_token_is_bound_to_auth_session():
    cookie_a = _signed_cookie("a" * 64)
    cookie_b = _signed_cookie("b" * 64)
    try:
        token_a = auth.csrf_token_for_session(cookie_a)
        token_b = auth.csrf_token_for_session(cookie_b)
        assert token_a and token_b and token_a != token_b
        assert auth.verify_csrf_token(cookie_a, token_a)
        assert not auth.verify_csrf_token(cookie_b, token_a)
        assert not auth.verify_csrf_token(cookie_a, "not-the-token")
    finally:
        auth._sessions.pop("a" * 64, None)
        auth._sessions.pop("b" * 64, None)


def test_authenticated_same_origin_mutation_requires_session_csrf_token(monkeypatch):
    cookie = _signed_cookie("c" * 64)
    token = auth.csrf_token_for_session(cookie)
    monkeypatch.setattr(auth, "is_auth_enabled", lambda: True)
    try:
        with _client(cookie) as client:
            missing = client.post(
                "/api/session/new",
                json={},
                headers={"Origin": "http://testserver", "Host": "testserver"},
            )
            accepted = client.post(
                "/api/session/new",
                json={},
                headers={
                    "Origin": "http://testserver",
                    "Host": "testserver",
                    auth.CSRF_HEADER_NAME: token,
                },
            )
        assert missing.status_code == 403
        assert accepted.status_code == 200
    finally:
        auth._sessions.pop("c" * 64, None)


def test_authenticated_public_origin_accepts_valid_token_when_allowed(monkeypatch):
    cookie = _signed_cookie("f" * 64)
    token = auth.csrf_token_for_session(cookie)
    monkeypatch.setattr(auth, "is_auth_enabled", lambda: True)
    monkeypatch.setenv("ARES_WEBUI_ALLOWED_ORIGINS", "https://myapp.example.com:8000")
    try:
        with _client(cookie) as client:
            response = client.post(
                "/api/session/new",
                json={},
                headers={
                    "Origin": "https://myapp.example.com:8000",
                    "Host": "proxy.internal",
                    auth.CSRF_HEADER_NAME: token,
                },
            )
        assert response.status_code == 200
    finally:
        auth._sessions.pop("f" * 64, None)


def test_forwarded_host_is_ignored_without_proxy_opt_in(monkeypatch):
    cookie = _signed_cookie("h" * 64)
    token = auth.csrf_token_for_session(cookie)
    monkeypatch.setattr(auth, "is_auth_enabled", lambda: True)
    monkeypatch.delenv("ARES_WEBUI_TRUST_FORWARDED_HOST", raising=False)
    try:
        with _client(cookie) as client:
            response = client.post(
                "/api/session/new",
                json={},
                headers={
                    "Origin": "https://example.com",
                    "Host": "127.0.0.1:8787",
                    "X-Forwarded-Host": "example.com:443",
                    auth.CSRF_HEADER_NAME: token,
                },
            )
        assert response.status_code == 403
    finally:
        auth._sessions.pop("h" * 64, None)


def test_non_browser_authenticated_mutation_remains_compatible(monkeypatch):
    cookie = _signed_cookie("d" * 64)
    token = auth.csrf_token_for_session(cookie)
    monkeypatch.setattr(auth, "is_auth_enabled", lambda: True)
    try:
        with _client(cookie) as client:
            response = client.post(
                "/api/session/new",
                json={},
                headers={auth.CSRF_HEADER_NAME: token},
            )
        assert response.status_code == 200
    finally:
        auth._sessions.pop("d" * 64, None)


def test_login_route_is_csrf_exempt(monkeypatch):
    monkeypatch.setattr(auth, "is_auth_enabled", lambda: False)
    with TestClient(create_app()) as client:
        response = client.post(
            "/api/auth/login",
            json={},
            headers={"Origin": "http://evil.example", "Host": "testserver"},
        )
    assert response.status_code == 400
    assert response.json()["error"] == "Invalid request"


def test_index_shell_includes_csrf_fetch_and_sendbeacon_injection():
    from pathlib import Path

    frontend = Path(__file__).resolve().parents[1] / "frontend"
    index = (frontend / "index.html").read_text(encoding="utf-8")
    api_client = (frontend / "src/shared/api-client.ts").read_text(encoding="utf-8")
    assert "__ARES_RUNTIME_CONFIG_JSON__" in index
    assert 'headers.set("X-CSRF-Token", token)' in api_client


def test_index_shell_injects_session_bound_csrf_token(monkeypatch, tmp_path):
    cookie = _signed_cookie("e" * 64)
    token = auth.csrf_token_for_session(cookie)
    monkeypatch.setattr(auth, "is_auth_enabled", lambda: True)
    frontend = tmp_path / "dist"
    frontend.mkdir()
    (frontend / "index.html").write_text(
        "csrfToken:__ARES_RUNTIME_CONFIG_JSON__",
        encoding="utf-8",
    )
    try:
        with _client(cookie, frontend_root=frontend) as client:
            response = client.get("/")
        assert response.status_code == 200
        assert f'csrfToken:{{csrfToken:"{token}"}}' in response.text
    finally:
        auth._sessions.pop("e" * 64, None)
