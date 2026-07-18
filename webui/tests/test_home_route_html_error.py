"""The React shell fails as HTML, never as an API-shaped JSON page."""

from pathlib import Path

from fastapi.testclient import TestClient

from fastapi_app.main import create_app


def test_home_route_internal_error_returns_html_503_not_json(monkeypatch, tmp_path):
    index = tmp_path / "index.html"
    index.write_text("<!doctype html><title>ARES</title>", encoding="utf-8")
    original = Path.read_text

    def failed_read(path, *args, **kwargs):
        if path.resolve() == index.resolve():
            raise OSError("simulated read failure")
        return original(path, *args, **kwargs)

    monkeypatch.setattr(Path, "read_text", failed_read)
    with TestClient(create_app(frontend_root=tmp_path)) as client:
        response = client.get("/")
    assert response.status_code == 503
    assert response.headers["content-type"].startswith("text/html")
    assert response.headers["cache-control"] == "no-store"
    assert "Ares is restarting" in response.text
    assert '"error"' not in response.text
