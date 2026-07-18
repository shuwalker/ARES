"""FastAPI cookie-session authentication contracts."""

from pathlib import Path

from fastapi.testclient import TestClient

from fastapi_app.main import create_app


def _frontend(tmp_path: Path) -> Path:
    root = tmp_path / "dist"
    root.mkdir()
    (root / "index.html").write_text("<div id='root'></div>", encoding="utf-8")
    return root


def _stub_password_auth(monkeypatch):
    monkeypatch.setattr("api.auth.is_auth_enabled", lambda: True)
    monkeypatch.setattr("api.auth.is_oidc_auth_enabled", lambda: False)
    monkeypatch.setattr("api.auth.get_password_hash", lambda: "configured")
    monkeypatch.setattr("api.auth._resolve_cookie_name", lambda: "ares_session")
    monkeypatch.setattr("api.auth._resolve_session_ttl", lambda: 3600)
    monkeypatch.setattr("api.auth._check_login_rate", lambda _ip: True)
    monkeypatch.setattr("api.auth._record_login_attempt", lambda _ip: None)
    monkeypatch.setattr("api.auth._clear_login_attempts", lambda _ip: None)
    monkeypatch.setattr("api.auth.verify_password", lambda password: password == "correct")
    monkeypatch.setattr("api.auth.create_session", lambda **_kwargs: "signed-cookie")
    monkeypatch.setattr("api.auth.verify_session", lambda value: value == "signed-cookie")


def test_password_login_establishes_fastapi_cookie_session(tmp_path, monkeypatch):
    _stub_password_auth(monkeypatch)
    app = create_app(frontend_root=_frontend(tmp_path))

    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        before = client.get("/api/auth/status")
        login = client.post("/api/auth/login", json={"password": "correct"})
        after = client.get("/api/auth/status")

    assert before.json()["logged_in"] is False
    assert login.status_code == 200
    assert "ares_session=signed-cookie" in login.headers["set-cookie"]
    assert after.json()["logged_in"] is True


def test_password_login_rejects_bad_credentials(tmp_path, monkeypatch):
    _stub_password_auth(monkeypatch)
    app = create_app(frontend_root=_frontend(tmp_path))

    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        response = client.post("/api/auth/login", json={"password": "wrong"})

    assert response.status_code == 401
    assert response.json()["error"] == "Invalid password"


def test_oidc_start_and_callback_establish_cookie(tmp_path, monkeypatch):
    monkeypatch.setattr(
        "api.auth_oidc.build_authorization_redirect",
        lambda base, next_path: f"https://identity.example/authorize?next={next_path}",
    )
    monkeypatch.setattr(
        "api.auth_oidc.complete_authorization_code_flow",
        lambda base, state, code: {"next_path": "/workspace"},
    )
    monkeypatch.setattr("api.auth.create_session", lambda **_kwargs: "oidc-cookie")
    monkeypatch.setattr("api.auth._resolve_session_ttl", lambda: 3600)
    app = create_app(frontend_root=_frontend(tmp_path))

    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        start = client.get("/api/auth/oidc/start?next=/workspace", follow_redirects=False)
        callback = client.get(
            "/api/auth/oidc/callback?state=state-1&code=code-1",
            follow_redirects=False,
        )

    assert start.status_code == 302
    assert start.headers["location"].startswith("https://identity.example/authorize")
    assert callback.status_code == 302
    assert callback.headers["location"] == "/workspace"
    assert "ares_session=oidc-cookie" in callback.headers["set-cookie"]


def test_local_first_passkey_registration_options_are_available(tmp_path, monkeypatch):
    monkeypatch.setattr("api.auth._passkey_feature_flag_enabled", lambda: True)
    monkeypatch.setattr("api.auth.is_auth_enabled", lambda: False)
    monkeypatch.setattr(
        "api.passkeys.registration_options",
        lambda request: {"challenge": "challenge-1", "rp": {"id": "testserver"}},
    )
    app = create_app(frontend_root=_frontend(tmp_path))

    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        response = client.post("/api/auth/passkey/register/options")

    assert response.status_code == 200
    assert response.json()["publicKey"]["challenge"] == "challenge-1"


def test_trusted_header_status_establishes_bound_session(tmp_path, monkeypatch):
    monkeypatch.setattr("api.auth.is_auth_enabled", lambda: True)
    monkeypatch.setattr("api.auth.is_oidc_auth_enabled", lambda: False)
    monkeypatch.setattr("api.auth.is_trusted_auth_enabled", lambda: True)
    monkeypatch.setattr("api.auth.get_password_hash", lambda: None)
    monkeypatch.setattr("api.auth._passkey_feature_flag_enabled", lambda: False)
    monkeypatch.setattr("api.auth._trusted_auth_username", lambda request: "owner@example.test")
    monkeypatch.setattr("api.auth._trusted_auth_bound_profile", lambda request: "default")
    monkeypatch.setattr("api.auth.create_session", lambda **kwargs: "trusted-cookie")
    monkeypatch.setattr("api.auth.verify_session", lambda value: value == "trusted-cookie")
    monkeypatch.setattr(
        "api.auth.get_session_info",
        lambda value: {
            "auth_type": "trusted",
            "username": "owner@example.test",
            "bound_profile": "default",
        }
        if value == "trusted-cookie"
        else None,
    )
    monkeypatch.setattr("api.network_trust.raw_peer_is_trusted_proxy", lambda request: True)
    monkeypatch.setattr("api.helpers.build_profile_cookie", lambda *args, **kwargs: "ares_profile=default")
    app = create_app(frontend_root=_frontend(tmp_path))

    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        response = client.get("/api/auth/status")

    assert response.status_code == 200
    assert response.json()["logged_in"] is True
    assert response.json()["auth_type"] == "trusted"
    assert response.json()["bound_profile"] == "default"
    assert "ares_session=trusted-cookie" in response.headers["set-cookie"]
