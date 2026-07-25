"""FastAPI onboarding route parity and first-run network boundaries."""

from pathlib import Path

from fastapi.testclient import TestClient

from fastapi_app.main import create_app


def _frontend(tmp_path: Path) -> Path:
    root = tmp_path / "dist"
    root.mkdir()
    (root / "index.html").write_text("<div id='root'></div>", encoding="utf-8")
    return root


def test_status_and_setup_use_domain_contracts(tmp_path, monkeypatch):
    monkeypatch.setattr("api.auth.is_auth_enabled", lambda: False)
    monkeypatch.setattr("api.onboarding.get_onboarding_status", lambda: {"completed": False})
    monkeypatch.setattr(
        "api.onboarding.apply_onboarding_setup",
        lambda payload: {"ok": True, "provider": payload["provider"]},
    )
    app = create_app(frontend_root=_frontend(tmp_path))

    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        status = client.get("/api/onboarding/status")
        setup = client.post("/api/onboarding/setup", json={"provider": "openai"})

    assert status.status_code == 200
    assert status.json() == {"completed": False}
    assert setup.status_code == 200
    assert setup.json() == {"ok": True, "provider": "openai"}


def test_passwordless_public_setup_is_rejected(tmp_path, monkeypatch):
    monkeypatch.setattr("api.auth.is_auth_enabled", lambda: False)
    monkeypatch.delenv("ARES_WEBUI_ONBOARDING_OPEN", raising=False)
    app = create_app(frontend_root=_frontend(tmp_path))

    with TestClient(app, client=("8.8.8.8", 50000)) as client:
        response = client.post("/api/onboarding/setup", json={"provider": "openai"})

    assert response.status_code == 403
    assert "local networks" in response.json()["error"]


def test_probe_does_not_write_configuration(tmp_path, monkeypatch):
    monkeypatch.setattr("api.auth.is_auth_enabled", lambda: False)
    captured = {}

    def fake_probe(provider, base_url, api_key):
        captured.update(provider=provider, base_url=base_url, api_key=api_key)
        return {"ok": True, "models": ["local-model"]}

    monkeypatch.setattr("api.onboarding.probe_provider_endpoint", fake_probe)
    app = create_app(frontend_root=_frontend(tmp_path))

    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        response = client.post(
            "/api/onboarding/probe",
            json={"provider": "CUSTOM", "base_url": "http://localhost:11434", "api_key": "k"},
        )

    assert response.status_code == 200
    assert response.json()["models"] == ["local-model"]
    assert captured == {
        "provider": "custom",
        "base_url": "http://localhost:11434",
        "api_key": "k",
    }

