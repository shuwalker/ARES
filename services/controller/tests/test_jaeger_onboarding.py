"""Tests for JaegerAI onboarding and peer-runtime status endpoints."""

from __future__ import annotations

from types import SimpleNamespace
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

from fastapi_app.main import app

client = TestClient(app)


def test_jaeger_onboarding_characters_endpoint():
    response = client.get("/api/jaeger-onboarding/characters")
    assert response.status_code == 200
    data = response.json()
    assert "characters" in data
    assert isinstance(data["characters"], list)


def test_jaeger_onboarding_models_endpoint_marks_recommendations_only():
    response = client.get("/api/jaeger-onboarding/models")
    assert response.status_code == 200
    data = response.json()
    assert "awake" in data
    assert "asleep" in data
    assert "registry_key" in data["awake"]
    assert "registry_key" in data["asleep"]
    # UI must never treat these as active/installed models.
    assert data.get("recommendations_only") is True


def test_jaeger_status_endpoint_shape():
    response = client.get("/api/jaeger-onboarding/status")
    assert response.status_code == 200
    data = response.json()
    assert "state" in data
    assert "provider_state" in data
    assert "available" in data
    assert "message" in data
    assert "checked_at" in data
    assert "instances" in data
    assert isinstance(data["instances"], list)
    assert "models_are_live" in data
    # Recommendations must not be embedded as active models.
    assert "awake" not in data
    assert "asleep" not in data


def test_jaeger_status_ready_from_provider_contract():
    fake = SimpleNamespace(
        state=SimpleNamespace(value="connected"),
        available=True,
        message="JaegerAI gateway is responding.",
        details={
            "mode": "gateway",
            "gateway_url": "http://127.0.0.1:8643",
            "model": "local-test-model",
            "instance": "athena",
            "booted": True,
        },
    )
    with (
        patch("api.providers.jaeger.status.check_status", return_value=fake),
        patch("api.providers.jaeger.status.reset_cache"),
        patch("api.providers.jaeger.companion.companion_exists", return_value=True),
    ):
        response = client.get("/api/jaeger-onboarding/status?refresh=true")
    assert response.status_code == 200
    data = response.json()
    assert data["state"] == "ready"
    assert data["provider_state"] == "connected"
    assert data["available"] is True
    assert data["active_model"] == "local-test-model"
    assert data["active_instance"] == "athena"
    assert data["transport_mode"] == "gateway"
    assert data["models_are_live"] is True
    assert data["companion_ready"] is True


def test_jaeger_status_not_installed():
    fake = SimpleNamespace(
        state=SimpleNamespace(value="not_installed"),
        available=False,
        message="JaegerAI is not installed.",
        details={},
    )
    with patch("api.providers.jaeger.status.check_status", return_value=fake):
        response = client.get("/api/jaeger-onboarding/status")
    assert response.status_code == 200
    data = response.json()
    assert data["state"] == "not_installed"
    assert data["available"] is False
    assert data["active_model"] is None
    assert data["models_are_live"] is False


def test_jaeger_status_offline_is_installed_but_stopped():
    fake = SimpleNamespace(
        state=SimpleNamespace(value="offline"),
        available=False,
        message="Gateway configured but not responding.",
        details={"mode": "gateway", "gateway_url": "http://127.0.0.1:8643"},
    )
    with patch("api.providers.jaeger.status.check_status", return_value=fake):
        response = client.get("/api/jaeger-onboarding/status")
    assert response.status_code == 200
    data = response.json()
    assert data["state"] == "installed_but_stopped"
    assert data["available"] is False
    assert data["gateway_url"] == "http://127.0.0.1:8643"


def test_jaeger_status_provider_error():
    with patch(
        "api.providers.jaeger.status.check_status",
        side_effect=RuntimeError("probe exploded"),
    ):
        response = client.get("/api/jaeger-onboarding/status")
    assert response.status_code == 200
    data = response.json()
    assert data["state"] == "error"
    assert data["available"] is False
    assert "probe exploded" in data["message"]
