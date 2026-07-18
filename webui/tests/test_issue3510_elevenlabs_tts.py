"""Service and FastAPI coverage for the ElevenLabs TTS engine (#3510)."""

import json
from urllib.request import HTTPRedirectHandler, ProxyHandler

import pytest

import api.tts_service as tts


class Response:
    def __init__(self, chunks, content_type="audio/mpeg"):
        self.headers = {"Content-Type": content_type} if content_type else {}
        self.chunks = iter(chunks)

    def read(self, _size=-1):
        return next(self.chunks, b"")

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False


def test_elevenlabs_missing_key_returns_503(monkeypatch, tmp_path):
    monkeypatch.delenv("ELEVENLABS_API_KEY", raising=False)
    import api.profiles as profiles

    monkeypatch.setattr(profiles, "get_active_ares_home", lambda: tmp_path)
    with pytest.raises(tts.TtsServiceError, match="ELEVENLABS_API_KEY") as raised:
        tts.generate_tts({"text": "hello", "engine": "elevenlabs"})
    assert raised.value.status_code == 503


def test_elevenlabs_rejects_traversal_voice_id(monkeypatch):
    monkeypatch.setenv("ELEVENLABS_API_KEY", "sk-test")
    import api.config as config

    monkeypatch.setattr(config, "get_config", lambda: {"tts": {"elevenlabs": {"voice_id": "../../etc/passwd"}}})
    with pytest.raises(tts.TtsServiceError, match="voice_id") as raised:
        tts.generate_tts({"text": "hello", "engine": "elevenlabs"})
    assert raised.value.status_code == 400


def test_elevenlabs_happy_path_streams_mp3(monkeypatch):
    monkeypatch.setenv("ELEVENLABS_API_KEY", "sk-test")
    import api.config as config

    monkeypatch.setattr(
        config,
        "get_config",
        lambda: {"tts": {"elevenlabs": {"voice_id": "voice_1", "model": "eleven_multilingual_v2"}}},
    )
    captured = {}

    def fake_open(request, **kwargs):
        captured["url"] = request.full_url
        captured["key"] = request.get_header("Xi-api-key")
        captured["body"] = json.loads(request.data)
        return Response([b"ID3fakeaudio"])

    monkeypatch.setattr(tts, "tts_open", fake_open)
    result = tts.generate_tts({"text": "hello world", "engine": "elevenlabs"})
    assert result.content == b"ID3fakeaudio"
    assert "voice_1" in captured["url"]
    assert captured["key"] == "sk-test"
    assert captured["body"]["text"] == "hello world"


def test_elevenlabs_overlong_text_rejected_before_upstream(monkeypatch):
    monkeypatch.setenv("ELEVENLABS_API_KEY", "sk-test")
    monkeypatch.setattr(tts, "tts_open", lambda *_args, **_kwargs: pytest.fail("upstream called"))
    with pytest.raises(tts.TtsServiceError, match="too long"):
        tts.generate_tts({"text": "x" * 5001, "engine": "elevenlabs"})


def test_elevenlabs_rejects_oversized_upstream_audio(monkeypatch):
    monkeypatch.setenv("ELEVENLABS_API_KEY", "sk-test")
    monkeypatch.setattr(tts, "TTS_PROXY_MAX_BYTES", 4)
    monkeypatch.setattr(tts, "tts_open", lambda *_args, **_kwargs: Response([b"1234", b"5"]))
    with pytest.raises(tts.TtsServiceError, match="generation failed") as raised:
        tts.generate_tts({"text": "hello", "engine": "elevenlabs"})
    assert raised.value.status_code == 502


def test_elevenlabs_blocks_redirects(monkeypatch):
    monkeypatch.setenv("ELEVENLABS_API_KEY", "sk-test")

    def fake_open(request, *, opener_factory, **kwargs):
        opener = opener_factory()
        handler = next(item for item in opener.handlers if isinstance(item, HTTPRedirectHandler))
        with pytest.raises(ValueError):
            handler.redirect_request(
                request,
                None,
                302,
                "Found",
                {"Location": "http://169.254.169.254/latest/meta-data"},
                "http://169.254.169.254/latest/meta-data",
            )
        raise ValueError("redirect blocked")

    monkeypatch.setattr(tts, "tts_open", fake_open)
    with pytest.raises(tts.TtsServiceError) as raised:
        tts.generate_tts({"text": "hello", "engine": "elevenlabs"})
    assert raised.value.status_code == 502


def test_elevenlabs_uses_no_proxy_opener(monkeypatch):
    monkeypatch.setenv("ELEVENLABS_API_KEY", "sk-test")
    captured = {}
    original = tts.ProxyHandler

    def proxy_handler(proxies=None, **kwargs):
        captured["proxies"] = proxies
        return original(proxies)

    def fake_open(_request, *, opener_factory, **kwargs):
        opener = opener_factory()
        captured["handlers"] = opener.handlers
        return Response([b"ID3fakeaudio"])

    monkeypatch.setattr(tts, "ProxyHandler", proxy_handler)
    monkeypatch.setattr(tts, "tts_open", fake_open)
    assert tts.generate_tts({"text": "hello", "engine": "elevenlabs"}).content == b"ID3fakeaudio"
    assert captured["proxies"] == {}
    assert any(isinstance(handler, HTTPRedirectHandler) for handler in captured["handlers"])
    assert not any(isinstance(handler, ProxyHandler) and handler.proxies for handler in captured["handlers"])
