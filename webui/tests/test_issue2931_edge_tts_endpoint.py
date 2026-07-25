"""FastAPI contract coverage for the Edge TTS endpoint (#2931)."""

import sys
from types import SimpleNamespace

import pytest
from fastapi.testclient import TestClient

from api.tts_service import tts_rate_limiter
from fastapi_app.main import create_app
from fastapi_app.request_context import RequestIdentity, require_identity


IDENTITY = RequestIdentity(session_cookie=None, profile="default", auth_enabled=False)


@pytest.fixture
def client(monkeypatch):
    monkeypatch.delenv("ARES_WEBUI_TRUST_FORWARDED_FOR", raising=False)
    tts_rate_limiter.clear()
    app = create_app()
    app.dependency_overrides[require_identity] = lambda: IDENTITY
    with TestClient(app, client=("10.0.0.1", 50000)) as test_client:
        yield test_client
    tts_rate_limiter.clear()


def test_tts_requires_post(client):
    assert client.get("/api/tts").status_code == 405


@pytest.mark.parametrize(
    ("payload", "message"),
    [
        ({"text": "   "}, "text is required"),
        ({"text": "x" * 5001}, "too long"),
        ({"text": "hello", "voice": "evil-voice-injection"}, "invalid voice"),
        ({"text": "hello", "rate": "<break/>"}, "invalid rate"),
        ({"text": "hello", "pitch": "+500Hz"}, "invalid pitch"),
    ],
)
def test_tts_rejects_invalid_input(client, payload, message):
    response = client.post("/api/tts", json=payload)
    assert response.status_code == 400
    assert message in response.json()["error"]


def test_tts_accepts_ui_prosody_shape(client, monkeypatch):
    captured = {}

    class FakeCommunicate:
        def __init__(self, text, voice, **kwargs):
            captured.update(text=text, voice=voice, kwargs=kwargs)

        def stream_sync(self):
            yield {"type": "audio", "data": b"abc"}

    monkeypatch.setitem(sys.modules, "edge_tts", SimpleNamespace(Communicate=FakeCommunicate))
    response = client.post(
        "/api/tts",
        json={"text": "hello", "voice": "en-US-AriaNeural", "rate": "+10%", "pitch": "-5Hz"},
    )
    assert response.status_code == 200
    assert response.content == b"abc"
    assert captured == {
        "text": "hello",
        "voice": "en-US-AriaNeural",
        "kwargs": {"rate": "+10%", "pitch": "-5Hz"},
    }


def test_tts_rate_limits_same_peer(client):
    first = client.post("/api/tts", json={"text": "hello", "voice": "invalid"})
    second = client.post("/api/tts", json={"text": "hello", "voice": "invalid"})
    assert first.status_code == 400
    assert second.status_code == 429


def test_tts_rate_limit_ignores_forwarded_for_by_default(client):
    first = client.post(
        "/api/tts", json={"text": "hello", "voice": "invalid"}, headers={"X-Forwarded-For": "203.0.113.10"}
    )
    second = client.post(
        "/api/tts", json={"text": "hello", "voice": "invalid"}, headers={"X-Forwarded-For": "203.0.113.11"}
    )
    assert first.status_code == 400
    assert second.status_code == 429


def test_tts_rate_limit_can_trust_forwarded_for(client, monkeypatch):
    monkeypatch.setenv("ARES_WEBUI_TRUST_FORWARDED_FOR", "1")
    first = client.post(
        "/api/tts", json={"text": "hello", "voice": "invalid"}, headers={"X-Forwarded-For": "203.0.113.12"}
    )
    second = client.post(
        "/api/tts", json={"text": "hello", "voice": "invalid"}, headers={"X-Forwarded-For": "203.0.113.13"}
    )
    assert first.status_code == 400
    assert second.status_code == 400
