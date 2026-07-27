import json

from fastapi.testclient import TestClient

from fastapi_app.main import create_app


def test_secret_values_never_enter_registry_or_list_response(monkeypatch, tmp_path):
    vault: dict[tuple[str | None, str], str] = {}
    path = tmp_path / "secrets.default.json"
    monkeypatch.setattr("fastapi_app.routers.secrets._secrets_file", lambda profile: path)
    monkeypatch.setattr("fastapi_app.routers.secrets.vault_set", lambda profile, key, value: vault.__setitem__((profile, key), value))
    monkeypatch.setattr("fastapi_app.routers.secrets.vault_get", lambda profile, key: vault[(profile, key)])
    monkeypatch.setattr("fastapi_app.routers.secrets.vault_delete", lambda profile, key: vault.pop((profile, key), None))

    with TestClient(create_app(), client=("127.0.0.1", 50000)) as client:
        created = client.post("/api/secrets", json={"key": "OPENAI_API_KEY", "value": "sk-secret-value"})
        assert created.status_code == 200
        assert "value" not in created.json()
        assert created.json()["provider"] == "os_keychain"
        assert "sk-secret-value" not in path.read_text(encoding="utf-8")

        listed = client.get("/api/secrets")
        assert listed.status_code == 200
        assert "value" not in listed.json()[0]

        revealed = client.get("/api/secrets/by-key/OPENAI_API_KEY")
        assert revealed.status_code == 200
        assert revealed.json()["value"] == "sk-secret-value"

        deleted = client.request("DELETE", "/api/secrets", json={"key": "OPENAI_API_KEY"})
        assert deleted.status_code == 200
        assert deleted.json() == []
        assert vault == {}


def test_legacy_plaintext_secret_migrates_before_response(monkeypatch, tmp_path):
    path = tmp_path / "secrets.default.json"
    path.write_text(json.dumps([{
        "id": "legacy", "name": "", "key": "LEGACY_TOKEN", "value": "plaintext",
        "provider": "local_encrypted", "status": "active", "created_at": "2026-01-01T00:00:00Z",
        "updated_at": "2026-01-01T00:00:00Z",
    }]), encoding="utf-8")
    vault: dict[tuple[str | None, str], str] = {}
    monkeypatch.setattr("fastapi_app.routers.secrets._secrets_file", lambda profile: path)
    monkeypatch.setattr("fastapi_app.routers.secrets.vault_set", lambda profile, key, value: vault.__setitem__((profile, key), value))

    with TestClient(create_app(), client=("127.0.0.1", 50000)) as client:
        response = client.get("/api/secrets")
        assert response.status_code == 200
        assert "value" not in response.json()[0]
        assert response.json()[0]["provider"] == "os_keychain"

    assert next(value for (_profile, key), value in vault.items() if key == "LEGACY_TOKEN") == "plaintext"
    assert "plaintext" not in path.read_text(encoding="utf-8")
