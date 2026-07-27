from fastapi.testclient import TestClient

from fastapi_app.main import create_app


def test_pairing_lifecycle_and_pending_cleanup_preserve_approved(monkeypatch, tmp_path):
    monkeypatch.setattr(
        "fastapi_app.routers.pairing._pairing_file",
        lambda profile: tmp_path / f"pairing.{profile or 'default'}.json",
    )

    with TestClient(create_app(), client=("127.0.0.1", 50000)) as client:
        forbidden = client.post("/api/connections/pairing/create", json={"name": "MacBook", "status": "approved"})
        assert forbidden.status_code == 400

        first = client.post("/api/connections/pairing/create", json={"name": "MacBook"})
        second = client.post("/api/connections/pairing/create", json={"name": "iPhone"})
        assert first.status_code == 200
        assert second.status_code == 200
        assert first.json()["status"] == "pending"

        approved = client.post("/api/connections/pairing/approve", json={"id": first.json()["id"]})
        assert approved.status_code == 200

        cleared = client.post("/api/connections/pairing/clear", json={})
        assert cleared.status_code == 200
        assert [entry["id"] for entry in cleared.json()] == [first.json()["id"]]
        assert cleared.json()[0]["status"] == "approved"

        revoked = client.post("/api/connections/pairing/revoke", json={"id": first.json()["id"]})
        assert revoked.status_code == 200
        assert revoked.json()[0]["status"] == "revoked"
