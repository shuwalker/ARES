"""Transport-neutral text-to-speech generation with bounded upstream access."""

from __future__ import annotations

import errno
import http.client
import ipaddress
import json
import os
import re
import socket
import sys
import threading
import time
from dataclasses import dataclass
from urllib.parse import urlsplit, urlunsplit
from urllib.request import (
    HTTPRedirectHandler,
    HTTPSHandler,
    ProxyHandler,
    Request,
    build_opener,
)


TTS_PROXY_MAX_BYTES = 16 * 1024 * 1024
TTS_LOCALHOST_HOSTS = {"127.0.0.1", "::1", "localhost"}
EDGE_VOICES = {
    "zh-CN-XiaoxiaoNeural",
    "zh-CN-XiaoyiNeural",
    "zh-CN-YunxiNeural",
    "zh-CN-YunjianNeural",
    "zh-CN-YunyangNeural",
    "en-US-AriaNeural",
    "en-US-GuyNeural",
    "fr-CA-AntoineNeural",
    "fr-CA-JeanNeural",
    "fr-CA-SylvieNeural",
    "fr-CA-ThierryNeural",
    "fr-FR-DeniseNeural",
    "fr-FR-EloiseNeural",
    "fr-FR-HenriNeural",
    "id-ID-GadisNeural",
}


class TtsServiceError(RuntimeError):
    def __init__(self, status_code: int, message: str):
        super().__init__(message)
        self.status_code = status_code


@dataclass(frozen=True)
class TtsAudio:
    content: bytes
    media_type: str = "audio/mpeg"


class TtsRateLimiter:
    def __init__(self, window_seconds: float = 2.0, prune_interval: int = 50):
        self.window = window_seconds
        self.prune_interval = prune_interval
        self._hits: dict[str, float] = {}
        self._lock = threading.Lock()
        self._checks = 0

    def check(self, key: str) -> bool:
        now = time.time()
        with self._lock:
            self._checks += 1
            if self._checks % self.prune_interval == 0:
                cutoff = now - (self.window * 10)
                self._hits = {name: hit for name, hit in self._hits.items() if hit > cutoff}
            last = self._hits.get(key, 0)
            if now - last < self.window:
                return False
            self._hits[key] = now
            return True

    def clear(self) -> None:
        with self._lock:
            self._hits.clear()
            self._checks = 0


tts_rate_limiter = TtsRateLimiter()


def normalize_tts_prosody(value, *, unit: str) -> str | None:
    if not value:
        return ""
    normalized = str(value).strip()
    if not re.fullmatch(r"[+-]?\d{1,3}" + re.escape(unit), normalized):
        return None
    amount = int(normalized[: -len(unit)])
    return normalized if -100 <= amount <= 100 else None


def tts_addr_is_blocked(ip_str: str) -> bool:
    try:
        ip = ipaddress.ip_address(ip_str)
    except ValueError:
        return False
    return (
        not ip.is_global
        or ip.is_private
        or ip.is_loopback
        or ip.is_link_local
        or ip.is_reserved
        or ip.is_multicast
        or ip.is_unspecified
    )


def tts_host_is_blocked_target(hostname: str) -> bool:
    host = (hostname or "").strip().lower()
    if not host:
        return True
    try:
        ipaddress.ip_address(host)
        return tts_addr_is_blocked(host)
    except ValueError:
        pass
    try:
        infos = socket.getaddrinfo(host, None)
    except Exception:
        return False
    return any(info[4] and tts_addr_is_blocked(str(info[4][0])) for info in infos)


def tts_resolve_pinned_addresses(hostname: str, port: int | None) -> list[str]:
    host = (hostname or "").strip().lower()
    if not host:
        raise ValueError("invalid OpenAI TTS base_url host")
    try:
        infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    except Exception as exc:
        raise ValueError("could not resolve OpenAI TTS base_url host") from exc
    addresses: list[str] = []
    for info in infos:
        if not info[4]:
            continue
        address = str(info[4][0])
        if tts_addr_is_blocked(address):
            raise ValueError("resolved OpenAI TTS target is not allowed")
        addresses.append(address)
    if not addresses:
        raise ValueError("could not resolve OpenAI TTS base_url host")
    return addresses


def normalized_openai_tts_base_url(base_url: str) -> str:
    parsed = urlsplit(str(base_url or "").strip())
    hostname = (parsed.hostname or "").strip().lower()
    if parsed.username or parsed.password:
        raise ValueError("invalid OpenAI base_url in config")
    if not parsed.scheme or not parsed.netloc or parsed.query or parsed.fragment:
        raise ValueError("invalid OpenAI base_url in config")
    if parsed.scheme == "https":
        if tts_host_is_blocked_target(hostname):
            raise ValueError("invalid OpenAI base_url in config")
    elif not (parsed.scheme == "http" and hostname in TTS_LOCALHOST_HOSTS):
        raise ValueError("invalid OpenAI base_url in config")
    return urlunsplit((parsed.scheme, parsed.netloc, parsed.path.rstrip("/"), "", ""))


def buffer_tts_audio_response(resp, *, max_bytes: int | None = None) -> bytes:
    maximum = TTS_PROXY_MAX_BYTES if max_bytes is None else max_bytes
    headers = getattr(resp, "headers", None)
    content_type = ""
    if headers is not None:
        content_type = str(headers.get("Content-Type") or "")
    if not content_type:
        try:
            content_type = str(resp.info().get("Content-Type") or "")
        except Exception:
            pass
    if content_type and not content_type.lower().startswith("audio/"):
        raise ValueError("upstream returned non-audio content")
    audio = bytearray()
    while True:
        chunk = resp.read(65536)
        if not chunk:
            break
        audio.extend(chunk)
        if len(audio) > maximum:
            raise ValueError("upstream audio exceeded byte limit")
    return bytes(audio)


class NoRedirectTtsHandler(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise ValueError("OpenAI TTS upstream attempted a redirect")


class PinnedHTTPSConnection(http.client.HTTPSConnection):
    def connect(self):
        sys.audit("http.client.connect", self, self.host, self.port)
        last_error = None
        for pinned_host in tts_resolve_pinned_addresses(self.host, self.port):
            try:
                self.sock = socket.create_connection(
                    (pinned_host, self.port), self.timeout, self.source_address
                )
                break
            except OSError as exc:
                last_error = exc
        else:
            if last_error is not None:
                raise last_error
            raise OSError("could not connect to any pinned OpenAI TTS target")
        try:
            self.sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        except OSError as exc:
            if exc.errno != errno.ENOPROTOOPT:
                raise
        if self._tunnel_host:
            self._tunnel()
        server_hostname = self._tunnel_host or self.host
        self.sock = self._context.wrap_socket(self.sock, server_hostname=server_hostname)


class PinnedHTTPSHandler(HTTPSHandler):
    def https_open(self, req):
        return self.do_open(PinnedHTTPSConnection, req, context=self._context)


def tts_open(req, *, timeout=30, opener_factory=None):
    if opener_factory is not None:
        return opener_factory().open(req, timeout=timeout)
    from urllib.request import urlopen

    return urlopen(req, timeout=timeout)


def _configured_key(*names: str) -> str:
    for name in names:
        value = os.getenv(name, "").strip()
        if value:
            return value
    try:
        from api.onboarding import _load_env_file
        from api.profiles import get_active_ares_home

        values = _load_env_file(get_active_ares_home() / ".env")
        for name in names:
            if values.get(name):
                return values[name]
    except Exception:
        pass
    return ""


def _elevenlabs(text: str) -> TtsAudio:
    api_key = _configured_key("ELEVENLABS_API_KEY")
    if not api_key:
        raise TtsServiceError(503, "ELEVENLABS_API_KEY not configured")
    voice_id = "pNInz6obpgDQGcFmaJgB"
    model_id = "eleven_multilingual_v2"
    try:
        from api.config import get_config

        config = (get_config() or {}).get("tts", {}).get("elevenlabs", {})
        if isinstance(config, dict):
            voice_id = config.get("voice_id", voice_id)
            model_id = config.get("model", model_id) or config.get("model_id", model_id)
    except Exception:
        pass
    if not isinstance(voice_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]+", voice_id):
        raise TtsServiceError(400, "invalid voice_id in config")
    body = json.dumps(
        {
            "text": text,
            "model_id": model_id,
            "voice_settings": {"stability": 0.5, "similarity_boost": 0.75},
        }
    ).encode()
    request = Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}/stream?output_format=mp3_44100_128",
        data=body,
        headers={"xi-api-key": api_key, "Content-Type": "application/json", "Accept": "audio/mpeg"},
    )
    try:
        with tts_open(
            request,
            timeout=30,
            opener_factory=lambda: build_opener(ProxyHandler({}), NoRedirectTtsHandler()),
        ) as response:
            return TtsAudio(buffer_tts_audio_response(response))
    except ValueError as exc:
        raise TtsServiceError(502, "ElevenLabs TTS generation failed") from exc
    except Exception as exc:
        raise TtsServiceError(500, "ElevenLabs TTS generation failed") from exc


def _openai(text: str) -> TtsAudio:
    api_key = _configured_key("VOICE_TOOLS_OPENAI_KEY", "OPENAI_API_KEY")
    if not api_key:
        raise TtsServiceError(503, "OpenAI API key not configured")
    base_url = "https://api.openai.com/v1"
    model = "gpt-4o-mini-tts"
    voice = "alloy"
    try:
        from api.config import get_config

        config = (get_config() or {}).get("tts", {}).get("openai", {})
        if isinstance(config, dict):
            base_url = config.get("base_url") or base_url
            model = config.get("model") or model
            voice = config.get("voice") or voice
        base_url = normalized_openai_tts_base_url(base_url)
    except ValueError as exc:
        raise TtsServiceError(400, "invalid OpenAI base_url in config") from exc
    except Exception:
        base_url = normalized_openai_tts_base_url(base_url)
    request = Request(
        f"{base_url}/audio/speech",
        data=json.dumps({"model": model, "input": text, "voice": voice}).encode(),
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
            "Accept": "audio/mpeg",
        },
    )
    try:
        with tts_open(
            request,
            timeout=30,
            opener_factory=lambda: build_opener(
                ProxyHandler({}), NoRedirectTtsHandler(), PinnedHTTPSHandler()
            ),
        ) as response:
            return TtsAudio(buffer_tts_audio_response(response))
    except ValueError as exc:
        raise TtsServiceError(502, "OpenAI TTS generation failed") from exc
    except Exception as exc:
        raise TtsServiceError(500, "OpenAI TTS generation failed") from exc


def _edge(text: str, voice: str, rate: str, pitch: str) -> TtsAudio:
    if voice not in EDGE_VOICES:
        raise TtsServiceError(400, "invalid voice")
    try:
        import edge_tts
    except ImportError as exc:
        raise TtsServiceError(
            503,
            "Edge TTS engine not installed on the server. Install it with: pip install edge-tts",
        ) from exc
    kwargs = {}
    if rate:
        kwargs["rate"] = rate
    if pitch:
        kwargs["pitch"] = pitch
    try:
        audio = bytearray()
        for chunk in edge_tts.Communicate(text, voice, **kwargs).stream_sync():
            if chunk.get("type") == "audio" and chunk.get("data"):
                audio.extend(chunk["data"])
    except Exception as exc:
        raise TtsServiceError(500, "TTS generation failed") from exc
    if not audio:
        raise TtsServiceError(500, "TTS produced no audio")
    return TtsAudio(bytes(audio))


def generate_tts(payload: dict) -> TtsAudio:
    if not isinstance(payload, dict):
        raise TtsServiceError(400, "invalid request body")
    text = str(payload.get("text") or "").strip()
    voice = str(payload.get("voice") or "zh-CN-XiaoxiaoNeural")
    engine = str(payload.get("engine") or "edge").strip().lower()
    rate = normalize_tts_prosody(payload.get("rate"), unit="%")
    pitch = normalize_tts_prosody(payload.get("pitch"), unit="Hz")
    if rate is None:
        raise TtsServiceError(400, "invalid rate")
    if pitch is None:
        raise TtsServiceError(400, "invalid pitch")
    if not text:
        raise TtsServiceError(400, "text is required")
    if len(text) > 5000:
        raise TtsServiceError(400, "text too long (max 5000 characters)")
    if engine == "elevenlabs":
        return _elevenlabs(text)
    if engine == "openai":
        return _openai(text)
    return _edge(text, voice, rate, pitch)
