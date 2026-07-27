from fastapi.testclient import TestClient

from fastapi_app.main import create_app


def test_profiles_route_returns_active_profile(monkeypatch):
    import api.profiles as profiles

    expected_profiles = [{"name": "default", "is_default": True}]

    monkeypatch.setattr("api.auth.is_auth_enabled", lambda: False)
    monkeypatch.setattr(profiles, "list_profiles_api", lambda: expected_profiles)
    monkeypatch.setattr(profiles, "get_active_profile_name", lambda: "default")
    monkeypatch.setattr(profiles, "_is_isolated_profile_mode", lambda: False)

    with TestClient(create_app()) as client:
        response = client.get("/api/profiles")

    assert response.status_code == 200
    assert response.json() == {
        "profiles": expected_profiles,
        "active": "default",
        "single_profile_mode": False,
    }
