"""FastAPI preflight never advertises wider access than mutation policy."""

from fastapi.testclient import TestClient

from fastapi_app.main import create_app


def _preflight(headers):
    with TestClient(create_app()) as client:
        return client.options("/api/settings", headers=headers)


def test_no_origin_omits_cors_headers():
    assert "access-control-allow-origin" not in _preflight({}).headers


def test_same_origin_is_echoed_without_a_wildcard():
    response = _preflight(
        {"Origin": "http://127.0.0.1:8787", "Host": "127.0.0.1:8787"}
    )
    assert response.headers["access-control-allow-origin"] == "http://127.0.0.1:8787"
    assert response.headers["access-control-allow-origin"] != "*"
    assert response.headers["vary"] == "Origin"


def test_cross_site_origin_is_denied_even_when_host_matches():
    response = _preflight(
        {
            "Origin": "http://127.0.0.1:8787",
            "Host": "127.0.0.1:8787",
            "Sec-Fetch-Site": "cross-site",
        }
    )
    assert "access-control-allow-origin" not in response.headers


def test_explicit_public_origin_allowlist(monkeypatch):
    monkeypatch.setenv("ARES_WEBUI_ALLOWED_ORIGINS", "https://myapp.example.com:8000")
    allowed = _preflight(
        {"Origin": "https://myapp.example.com:8000", "Host": "127.0.0.1:8787"}
    )
    denied = _preflight(
        {"Origin": "https://evil.example.com:8000", "Host": "127.0.0.1:8787"}
    )
    assert allowed.headers["access-control-allow-origin"] == "https://myapp.example.com:8000"
    assert "access-control-allow-origin" not in denied.headers


def test_forwarded_host_requires_explicit_trust(monkeypatch):
    headers = {
        "Origin": "https://webui.example.com",
        "Host": "127.0.0.1:8787",
        "X-Forwarded-Host": "webui.example.com:443",
    }
    monkeypatch.delenv("ARES_WEBUI_TRUST_FORWARDED_HOST", raising=False)
    assert "access-control-allow-origin" not in _preflight(headers).headers
    monkeypatch.setenv("ARES_WEBUI_TRUST_FORWARDED_HOST", "1")
    assert _preflight(headers).headers["access-control-allow-origin"] == "https://webui.example.com"


def test_real_cross_origin_mutation_is_rejected():
    with TestClient(create_app()) as client:
        response = client.post(
            "/api/settings",
            headers={"Origin": "https://attacker.invalid", "Host": "testserver"},
            json={},
        )
    assert response.status_code == 403
    assert "Cross-origin" in response.json()["error"]
