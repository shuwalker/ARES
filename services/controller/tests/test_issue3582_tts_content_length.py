"""FastAPI TTS responses remain bounded and include an exact Content-Length."""

import sys
import types

import pytest
from fastapi.testclient import TestClient

from api.tts_service import tts_rate_limiter
from fastapi_app.main import create_app
from fastapi_app.request_context import RequestIdentity, require_identity


IDENTITY = RequestIdentity(session_cookie=None, profile="default", auth_enabled=False)


@pytest.fixture
def client():
    tts_rate_limiter.clear()
    app = create_app()
    app.dependency_overrides[require_identity] = lambda: IDENTITY
    with TestClient(app) as value:
        yield value
    tts_rate_limiter.clear()


def _mock_edge_tts(monkeypatch, chunks):
    module = types.ModuleType("edge_tts")

    class FakeCommunicate:
        def __init__(self, text, voice, **kwargs):
            pass

        def stream_sync(self):
            yield from chunks

    module.Communicate = FakeCommunicate
    monkeypatch.setitem(sys.modules, "edge_tts", module)


def test_content_length_present_and_correct(client, monkeypatch):
    audio = (b"\xff\xfb\x90" * 100) + (b"\xff\xfb\x90" * 50)
    _mock_edge_tts(monkeypatch, [{"type": "audio", "data": audio}])
    response = client.post("/api/tts", json={"text": "hello", "voice": "en-US-AriaNeural"})
    assert response.status_code == 200
    assert response.headers["content-length"] == str(len(audio))
    assert response.headers["content-type"] == "audio/mpeg"
    assert response.content == audio


def test_empty_audio_returns_500(client, monkeypatch):
    _mock_edge_tts(monkeypatch, [])
    response = client.post("/api/tts", json={"text": "silent", "voice": "en-US-AriaNeural"})
    assert response.status_code == 500
    assert "no audio" in response.json()["error"]


def test_non_audio_chunks_ignored(client, monkeypatch):
    audio = b"\xff\xfb" * 20
    _mock_edge_tts(
        monkeypatch,
        [
            {"type": "WordBoundary", "data": b"ignored"},
            {"type": "audio", "data": audio},
            {"type": "SessionEnd", "data": None},
        ],
    )
    response = client.post("/api/tts", json={"text": "mixed", "voice": "en-US-AriaNeural"})
    assert response.status_code == 200
    assert response.content == audio
