from pathlib import Path

from fastapi.testclient import TestClient

from fastapi_app.main import create_app
from fastapi_app.request_context import RequestIdentity, require_identity, require_mutation_identity


IDENTITY = RequestIdentity(session_cookie=None, profile="default", auth_enabled=False)


def test_product_state_is_profile_scoped_atomic_and_revision_guarded(tmp_path: Path, monkeypatch):
    monkeypatch.setattr("api.profiles.get_ares_home_for_profile", lambda _profile: tmp_path)
    app = create_app()
    app.dependency_overrides[require_identity] = lambda: IDENTITY
    app.dependency_overrides[require_mutation_identity] = lambda: IDENTITY

    with TestClient(app, client=("127.0.0.1", 50000)) as client:
        empty = client.get("/api/product-state/board")
        saved = client.put(
            "/api/product-state/board",
            json={"state": {"cards": [{"id": "one"}]}, "expected_revision": 0},
        )
        conflict = client.put(
            "/api/product-state/board",
            json={"state": {"cards": []}, "expected_revision": 0},
        )
        restored = client.get("/api/product-state/board")
        unknown = client.get("/api/product-state/not-a-module")

    assert empty.json() == {"module": "board", "revision": 0, "state": {}}
    assert saved.status_code == 200
    assert saved.json()["revision"] == 1
    assert conflict.status_code == 409
    assert conflict.json()["code"] == "product_state_conflict"
    assert restored.json()["state"]["cards"] == [{"id": "one"}]
    assert unknown.status_code == 400
    state_file = tmp_path / "webui" / "product-state" / "board.json"
    assert state_file.exists()
    assert state_file.stat().st_mode & 0o777 == 0o600
