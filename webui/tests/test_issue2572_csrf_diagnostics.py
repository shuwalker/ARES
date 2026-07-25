"""FastAPI CSRF failures remain specific enough to diagnose safely."""

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


def test_origin_mismatch_has_proxy_diagnostic(monkeypatch):
    monkeypatch.setattr(auth, "is_auth_enabled", lambda: False)
    with TestClient(create_app()) as client:
        response = client.post(
            "/api/providers/delete",
            headers={"Origin": "https://evil.example"},
            json={},
        )
    assert response.status_code == 403
    assert response.json()["error"] == "Cross-origin mismatch - check reverse proxy headers"


def test_token_mismatch_has_bounded_csrf_error(monkeypatch):
    raw_token = "z" * 64
    cookie = _signed_cookie(raw_token)
    monkeypatch.setattr(auth, "is_auth_enabled", lambda: True)
    try:
        with TestClient(create_app()) as client:
            client.cookies.set(auth.COOKIE_NAME, cookie)
            response = client.post(
                "/api/providers/delete",
                headers={"Origin": "http://testserver"},
                json={},
            )
        assert response.status_code == 403
        assert response.json()["error"] == "Invalid CSRF token"
    finally:
        auth._sessions.pop(raw_token, None)
