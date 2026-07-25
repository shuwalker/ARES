"""FastAPI CORS preflight framing and allowlist coverage."""

from fastapi.testclient import TestClient

from fastapi_app.main import create_app


def test_options_response_is_empty_and_framed():
    with TestClient(create_app()) as client:
        response = client.options("/api/settings")
    assert response.status_code == 200
    assert response.content == b""
    assert response.headers.get("content-length") == "0"


def test_same_origin_preflight_echoes_origin():
    with TestClient(create_app()) as client:
        response = client.options(
            "/api/settings",
            headers={"Origin": "http://testserver", "Host": "testserver"},
        )
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://testserver"
    assert "POST" in response.headers["access-control-allow-methods"]
    assert response.headers.get("content-length") == "0"


def test_disallowed_preflight_remains_headerless():
    with TestClient(create_app()) as client:
        response = client.options(
            "/api/settings",
            headers={"Origin": "https://attacker.invalid", "Host": "testserver"},
        )
    assert response.status_code == 200
    assert "access-control-allow-origin" not in response.headers
