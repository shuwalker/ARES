import io
import json
import socket
import time
from types import SimpleNamespace
from urllib.parse import parse_qs, urlparse

import pytest
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec, utils


class FakeHeaders(dict):
    def get(self, key, default=None):
        return super().get(key, default)


class RouteFakeHandler:
    def __init__(self):
        self.headers = FakeHeaders({"Host": "localhost:8787"})
        self.request = SimpleNamespace()
        self.wfile = io.BytesIO()
        self.status = None
        self.sent_headers = []

    def send_response(self, status):
        self.status = status

    def send_header(self, key, value):
        self.sent_headers.append((key, value))

    def end_headers(self):
        pass

    def json_body(self):
        return json.loads(self.wfile.getvalue().decode("utf-8"))

    def header_values(self, name):
        needle = name.lower()
        return [value for key, value in self.sent_headers if key.lower() == needle]

def _ec_jwk(private_key, *, kid="key-1", alg="ES256"):
    numbers = private_key.public_key().public_numbers()
    size = (numbers.curve.key_size + 7) // 8
    import api.auth_oidc as auth_oidc

    return {
        "kid": kid,
        "kty": "EC",
        "alg": alg,
        "crv": "P-256",
        "x": auth_oidc._b64u(numbers.x.to_bytes(size, "big")),
        "y": auth_oidc._b64u(numbers.y.to_bytes(size, "big")),
    }

def _signed_es256_jwt(private_key, header, claims):
    import api.auth_oidc as auth_oidc

    header_b64 = auth_oidc._b64u(json.dumps(header, separators=(",", ":")).encode("utf-8"))
    claims_b64 = auth_oidc._b64u(json.dumps(claims, separators=(",", ":")).encode("utf-8"))
    signed = f"{header_b64}.{claims_b64}".encode("ascii")
    der_signature = private_key.sign(signed, ec.ECDSA(hashes.SHA256()))
    r, s = utils.decode_dss_signature(der_signature)
    raw_signature = r.to_bytes(32, "big") + s.to_bytes(32, "big")
    return f"{header_b64}.{claims_b64}.{auth_oidc._b64u(raw_signature)}"














def test_oidc_enablement_requires_explicit_allowlist(monkeypatch):
    import api.auth_oidc as auth_oidc

    monkeypatch.delenv("ARES_WEBUI_OIDC_ISSUER", raising=False)
    monkeypatch.delenv("ARES_WEBUI_OIDC_CLIENT_ID", raising=False)
    monkeypatch.delenv("ARES_WEBUI_OIDC_ALLOW_CLAIM", raising=False)
    monkeypatch.delenv("ARES_WEBUI_OIDC_ALLOW_VALUES", raising=False)
    monkeypatch.setattr(
        auth_oidc,
        "get_config",
        lambda: {
            "webui_oidc": {
                "issuer": "https://issuer.example",
                "client_id": "webui-client",
            }
        },
    )

    assert auth_oidc.is_oidc_enabled() is False

def test_oidc_startup_warning_flags_partial_config(monkeypatch):
    import api.auth as auth

    monkeypatch.setattr(
        auth,
        "get_config",
        lambda: {
            "webui_oidc": {
                "issuer": "https://issuer.example",
                "client_id": "webui-client",
            }
        },
    )

    warning = auth.get_oidc_startup_warning()
    assert warning is not None
    assert "allow_claim" in warning
    assert "allow_values" in warning

def test_oidc_startup_warning_ignores_complete_config(monkeypatch):
    import api.auth as auth

    monkeypatch.setattr(
        auth,
        "get_config",
        lambda: {
            "webui_oidc": {
                "issuer": "https://issuer.example",
                "client_id": "webui-client",
                "allow_claim": "email",
                "allow_values": ["user@example.com"],
            }
        },
    )

    assert auth.get_oidc_startup_warning() is None

def test_validate_id_token_rejects_mismatched_jwk_key_family(monkeypatch):
    import api.auth_oidc as auth_oidc
    from api.auth_oidc import OIDCAuthError

    monkeypatch.setattr(
        auth_oidc,
        "_parse_jwt",
        lambda _token: (
            {"alg": "RS256", "kid": "key-1"},
            {
                "iss": "https://issuer.example",
                "aud": "webui-client",
                "exp": 32503680000,
                "nonce": "nonce-token",
                "sub": "user-123",
            },
            b"signed",
            b"signature",
        ),
    )
    monkeypatch.setattr(
        auth_oidc,
        "_get_jwks_document",
        lambda _jwks_uri, **_kwargs: {
            "keys": [
                {
                    "kid": "key-1",
                    "kty": "EC",
                    "crv": "P-256",
                    "x": "AQ",
                    "y": "Ag",
                }
            ]
        },
    )

    with pytest.raises(OIDCAuthError, match="did not contain the signing key"):
        auth_oidc._validate_id_token(
            "header.payload.signature",
            client_id="webui-client",
            issuer="https://issuer.example",
            nonce="nonce-token",
            jwks_uri="https://issuer.example/jwks",
        )

def test_validate_id_token_accepts_real_es256_jose_signature(monkeypatch):
    import api.auth_oidc as auth_oidc

    private_key = ec.generate_private_key(ec.SECP256R1())
    token = _signed_es256_jwt(
        private_key,
        {"alg": "ES256", "kid": "key-1"},
        {
            "iss": "https://issuer.example",
            "aud": "webui-client",
            "exp": 32503680000,
            "nonce": "nonce-token",
            "sub": "user-123",
        },
    )
    monkeypatch.setattr(
        auth_oidc,
        "_get_jwks_document",
        lambda _jwks_uri, **_kwargs: {"keys": [_ec_jwk(private_key)]},
    )

    claims = auth_oidc._validate_id_token(
        token,
        client_id="webui-client",
        issuer="https://issuer.example",
        nonce="nonce-token",
        jwks_uri="https://issuer.example/jwks",
    )

    assert claims["sub"] == "user-123"

def test_complete_authorization_pins_discovery_to_configured_issuer(monkeypatch):
    import api.auth_oidc as auth_oidc
    from api.auth_oidc import OIDCAuthError

    monkeypatch.setattr(
        auth_oidc,
        "_resolve_oidc_config",
        lambda: {
            "issuer": "https://issuer.example",
            "client_id": "webui-client",
            "client_secret": "",
            "redirect_uri": "",
            "scopes": ["openid"],
            "allow_claim": "email",
            "allow_values": ["user@example.com"],
        },
    )
    monkeypatch.setattr(
        auth_oidc,
        "_get_discovery_document",
        lambda _issuer: {
            "issuer": "https://evil.example",
            "token_endpoint": "https://issuer.example/token",
            "jwks_uri": "https://issuer.example/jwks",
        },
    )
    auth_oidc._pending_flows.clear()
    auth_oidc._pending_flows["state-token"] = {
        "created_at": time.time(),
        "nonce": "nonce-token",
        "code_verifier": "verifier",
        "next_path": "/",
    }

    with pytest.raises(OIDCAuthError, match="discovery issuer"):
        auth_oidc.complete_authorization_code_flow(
            "http://localhost:8787",
            "state-token",
            "code-token",
        )

def test_validate_id_token_refetches_jwks_once_on_key_miss(monkeypatch):
    import api.auth_oidc as auth_oidc

    old_key = ec.generate_private_key(ec.SECP256R1())
    new_key = ec.generate_private_key(ec.SECP256R1())
    token = _signed_es256_jwt(
        new_key,
        {"alg": "ES256", "kid": "new-key"},
        {
            "iss": "https://issuer.example",
            "aud": "webui-client",
            "exp": 32503680000,
            "nonce": "nonce-token",
            "sub": "user-123",
        },
    )
    jwks_uri = "https://issuer.example/jwks"
    auth_oidc._jwks_cache.clear()
    auth_oidc._jwks_cache[jwks_uri] = (
        time.time() + 300,
        {"keys": [_ec_jwk(old_key, kid="old-key")]},
    )
    fetches = []

    def fake_fetch_json(url):
        fetches.append(url)
        return {"keys": [_ec_jwk(new_key, kid="new-key")]}

    monkeypatch.setattr(auth_oidc, "_fetch_json", fake_fetch_json)

    claims = auth_oidc._validate_id_token(
        token,
        client_id="webui-client",
        issuer="https://issuer.example",
        nonce="nonce-token",
        jwks_uri=jwks_uri,
    )

    assert claims["sub"] == "user-123"
    assert fetches == [jwks_uri]

def test_pending_oidc_flows_are_bounded(monkeypatch):
    import api.auth_oidc as auth_oidc

    monkeypatch.setattr(auth_oidc, "_MAX_PENDING_FLOWS", 2)
    auth_oidc._pending_flows.clear()
    now = time.time()
    auth_oidc._store_pending_flow("old", {"created_at": now - 2, "nonce": "old"})
    auth_oidc._store_pending_flow("middle", {"created_at": now - 1, "nonce": "middle"})
    auth_oidc._store_pending_flow("new", {"created_at": now, "nonce": "new"})

    assert set(auth_oidc._pending_flows) == {"middle", "new"}


@pytest.mark.parametrize(
    ("url", "message"),
    [
        ("file:///etc/hostname/.well-known/openid-configuration", "must use https"),
        ("https://127.0.0.1/.well-known/openid-configuration", "private or local addresses"),
    ],
)
def test_fetch_json_rejects_unsafe_oidc_urls(url, message):
    import api.auth_oidc as auth_oidc
    from api.auth_oidc import OIDCAuthError

    with pytest.raises(OIDCAuthError, match=message):
        auth_oidc._fetch_json(url)


def test_fetch_json_rejects_dns_resolved_private_hosts(monkeypatch):
    import api.auth_oidc as auth_oidc
    from api.auth_oidc import OIDCAuthError

    monkeypatch.setattr(
        auth_oidc.socket,
        "getaddrinfo",
        lambda *_args, **_kwargs: [
            (socket.AF_INET, socket.SOCK_STREAM, 6, "", ("192.168.1.7", 443))
        ],
    )

    with pytest.raises(OIDCAuthError, match="private or local addresses"):
        auth_oidc._fetch_json("https://issuer.example/.well-known/openid-configuration")


def test_select_public_key_rejects_wrong_ec_curve_for_alg():
    import api.auth_oidc as auth_oidc
    from api.auth_oidc import OIDCAuthError

    private_key = ec.generate_private_key(ec.SECP256R1())
    jwks = {"keys": [_ec_jwk(private_key, alg="ES384")]}

    with pytest.raises(OIDCAuthError, match="did not contain the signing key"):
        auth_oidc._select_public_key(jwks, {"alg": "ES384", "kid": "key-1"})


@pytest.mark.parametrize("value", [float("nan"), float("inf"), float("-inf")])
def test_parse_jwt_rejects_non_finite_numeric_claims(value):
    import api.auth_oidc as auth_oidc
    from api.auth_oidc import OIDCAuthError

    header = auth_oidc._b64u(b'{"alg":"RS256"}')
    claims = auth_oidc._b64u(
        json.dumps({"exp": value}, separators=(",", ":")).encode("utf-8")
    )
    signature = auth_oidc._b64u(b"signature")
    token = f"{header}.{claims}.{signature}"

    with pytest.raises(OIDCAuthError, match="could not be decoded"):
        auth_oidc._parse_jwt(token)


@pytest.mark.parametrize("value", [float("nan"), float("inf"), float("-inf")])
def test_coerce_numeric_claim_rejects_non_finite_values(value):
    import api.auth_oidc as auth_oidc
    from api.auth_oidc import OIDCAuthError

    with pytest.raises(OIDCAuthError, match="claim exp was not numeric"):
        auth_oidc._coerce_numeric_claim({"exp": value}, "exp")
def test_oidc_start_redirects_with_pkce_state_and_nonce(monkeypatch):
    from fastapi.testclient import TestClient
    from fastapi_app.main import create_app

    monkeypatch.setattr(
        "api.auth_oidc.build_authorization_redirect",
        lambda request_base_url, next_path: (
            "https://idp.example/authorize?response_type=code&state=state-token"
            "&nonce=nonce-token&code_challenge=challenge-token&code_challenge_method=S256"
        ),
    )
    with TestClient(create_app(), follow_redirects=False) as client:
        response = client.get(
            "/api/auth/oidc/start",
            params={"next": "/projects?view=grid"},
            headers={"host": "localhost:8787"},
        )
    assert response.status_code == 302
    params = parse_qs(urlparse(response.headers["location"]).query)
    assert params["state"] == ["state-token"]
    assert params["nonce"] == ["nonce-token"]
    assert params["code_challenge_method"] == ["S256"]


def test_oidc_callback_sets_session_cookie(monkeypatch):
    from fastapi.testclient import TestClient
    from fastapi_app.main import create_app
    import api.auth as auth

    monkeypatch.setattr(
        "api.auth_oidc.complete_authorization_code_flow",
        lambda request_base_url, state, code: {"next_path": "/chat/123"},
    )
    monkeypatch.setattr(auth, "create_session", lambda **kwargs: "session-token.signature")
    with TestClient(create_app(), follow_redirects=False) as client:
        response = client.get(
            "/api/auth/oidc/callback?state=state-token&code=code-token",
            headers={"host": "localhost:8787"},
        )
    assert response.status_code == 302
    assert response.headers["location"] == "/chat/123"
    assert "session-token.signature" in response.headers["set-cookie"]


@pytest.mark.parametrize(
    ("message", "status"),
    [("Invalid OIDC state", 401), ("OIDC identity is not allowed", 403)],
)
def test_oidc_callback_rejects_invalid_identity(monkeypatch, message, status):
    from fastapi.testclient import TestClient
    from fastapi_app.main import create_app
    from api.auth_oidc import OIDCAuthError

    monkeypatch.setattr(
        "api.auth_oidc.complete_authorization_code_flow",
        lambda *_args: (_ for _ in ()).throw(OIDCAuthError(message, status_code=status)),
    )
    with TestClient(create_app(), follow_redirects=False) as client:
        response = client.get("/api/auth/oidc/callback?state=state&code=code")
    assert response.status_code == status
    assert response.json()["error"] == message
    assert "set-cookie" not in response.headers


def test_auth_status_reports_oidc_and_passkey_capabilities(monkeypatch):
    from fastapi.testclient import TestClient
    from fastapi_app.main import create_app
    import api.auth as auth

    monkeypatch.setattr(auth, "is_auth_enabled", lambda: True)
    monkeypatch.setattr(auth, "is_oidc_auth_enabled", lambda: True)
    monkeypatch.setattr(auth, "_passkey_feature_flag_enabled", lambda: False)
    monkeypatch.setattr(auth, "get_password_hash", lambda: None)
    with TestClient(create_app()) as client:
        response = client.get("/api/auth/status")
    assert response.status_code == 200
    payload = response.json()
    assert payload["oidc_enabled"] is True
    assert payload["passkeys_enabled"] is False
    assert payload["password_auth_enabled"] is False


