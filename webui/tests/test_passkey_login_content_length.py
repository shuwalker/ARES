"""ASGI passkey-login success responses are correctly framed."""

from __future__ import annotations

from fastapi.testclient import TestClient

import api.auth as auth
import api.passkeys as passkeys
from fastapi_app.main import create_app


def _successful_login(monkeypatch):
    monkeypatch.setattr(auth, "_passkey_feature_flag_enabled", lambda: True)
    monkeypatch.setattr(auth, "is_auth_enabled", lambda: True)
    monkeypatch.setattr(auth, "_check_login_rate", lambda _ip: True)
    monkeypatch.setattr(passkeys, "finish_login", lambda _body, _request: None)
    monkeypatch.setattr(auth, "create_session", lambda *args, **kwargs: "sess-cookie")
    with TestClient(create_app()) as client:
        return client.post("/api/auth/passkey/login", json={})


def test_passkey_login_success_sets_content_length(monkeypatch):
    response = _successful_login(monkeypatch)
    assert response.status_code == 200
    assert response.json() == {"ok": True}
    assert response.headers["content-length"] == str(len(response.content))


def test_passkey_login_sets_cookie_before_response_is_sent(monkeypatch):
    response = _successful_login(monkeypatch)
    assert response.status_code == 200
    assert "set-cookie" in response.headers
    assert "content-length" in response.headers
