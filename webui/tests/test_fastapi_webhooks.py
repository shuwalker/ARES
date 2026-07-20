from fastapi.testclient import TestClient

from fastapi_app.main import create_app


def test_webhook_create_partial_toggle_and_delete(monkeypatch, tmp_path):
    monkeypatch.setattr(
        "fastapi_app.routers.webhooks._webhooks_file",
        lambda profile: tmp_path / f"webhooks.{profile or 'default'}.json",
    )

    with TestClient(create_app(), client=("127.0.0.1", 50000)) as client:
        created = client.post(
            "/api/gateway/webhooks",
            json={"name": "notifications", "url": "https://example.test/hook", "event": "session.completed"},
        )
        assert created.status_code == 200
        webhook = created.json()

        toggled = client.patch(
            f"/api/gateway/webhooks/{webhook['id']}",
            json={"enabled": False},
        )
        assert toggled.status_code == 200
        assert toggled.json() == {**webhook, "enabled": False}

        listed = client.get("/api/gateway/webhooks")
        assert listed.status_code == 200
        assert listed.json() == [{**webhook, "enabled": False}]

        deleted = client.request(
            "DELETE",
            "/api/gateway/webhooks",
            json={"id": webhook["id"]},
        )
        assert deleted.status_code == 200
        assert deleted.json() == []
