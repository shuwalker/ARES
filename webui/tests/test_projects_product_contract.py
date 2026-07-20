from fastapi.testclient import TestClient

from fastapi_app.main import create_app
from fastapi_app.request_context import RequestIdentity, require_identity, require_mutation_identity


IDENTITY = RequestIdentity(session_cookie=None, profile="default", auth_enabled=False)


def test_project_metadata_create_update_and_delete_are_server_persisted(monkeypatch):
    rows = []
    monkeypatch.setattr("api.models.load_projects", lambda: rows)
    monkeypatch.setattr("api.models.save_projects", lambda values: rows.__setitem__(slice(None), values))
    monkeypatch.setattr("api.models.all_sessions", lambda: [])
    monkeypatch.setattr("api.profiles.get_active_profile_name", lambda: "default")
    monkeypatch.setattr("api.profiles._is_isolated_profile_mode", lambda: True)
    monkeypatch.setattr("api.profiles._profiles_match", lambda left, right: (left or "default") == (right or "default"))

    app = create_app()
    app.dependency_overrides[require_identity] = lambda: IDENTITY
    app.dependency_overrides[require_mutation_identity] = lambda: IDENTITY

    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        created = client.post(
            "/api/projects/create",
            json={
                "name": "Launch ARES",
                "description": "Ship a verified desktop build",
                "domain": "Product",
                "status": "active",
                "target_date": "2026-08-01",
            },
        )
        project_id = created.json()["project"]["project_id"]
        updated = client.post(
            "/api/projects/update",
            json={"project_id": project_id, "status": "on_hold", "domain": "Release"},
        )
        listed = client.get("/api/projects")
        rejected = client.post(
            "/api/projects/update",
            json={"project_id": project_id, "status": "invented"},
        )
        deleted = client.post("/api/projects/delete", json={"project_id": project_id})

    assert created.status_code == 200
    assert created.json()["project"]["description"] == "Ship a verified desktop build"
    assert updated.status_code == 200
    assert updated.json()["project"]["status"] == "on_hold"
    assert listed.json()["projects"][0]["domain"] == "Release"
    assert rejected.status_code == 400
    assert deleted.status_code == 200
    assert rows == []
