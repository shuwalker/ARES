"""Tests for JaegerAI onboarding endpoints."""

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


def test_jaeger_onboarding_models_endpoint():
    response = client.get("/api/jaeger-onboarding/models")
    assert response.status_code == 200
    data = response.json()
    assert "awake" in data
    assert "asleep" in data
    assert "registry_key" in data["awake"]
    assert "registry_key" in data["asleep"]


def test_jaeger_status_endpoint():
    response = client.get("/api/jaeger-onboarding/status")
    assert response.status_code == 200
    data = response.json()
    assert "jaeger_ai_available" in data
    assert "instances" in data
