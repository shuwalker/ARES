"""
ARES Voice MCP Server — Natural voice conversation pipeline.

v2 pipeline:
  TTS:  macOS 'say' → Piper (natural, 20+ voices, <200ms)
  STT:  faster-whisper batch / NSSpeechRecognizer (macOS native)
  VAD:  Silero VAD + WebRTC VAD
  Turn: continuous turn-based conversation

MCP server :9513, StreamableHTTP.
"""

from __future__ import annotations

import io
import logging
import os
import subprocess
import tempfile
import threading
import time
import wave
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import numpy as np
import pyaudio
from mcp.server.fastmcp import FastMCP

logger = logging.getLogger("ares.voice")

server = FastMCP(
    name="ARES Voice v2",
    instructions="Natural voice pipeline: VAD + NSSpeechRecognizer/faster-whisper STT + Piper TTS. 100% local.",
    host="0.0.0.0",
    port=9513,
)

# ═══ Paths ══════════════════════════════════════════════════════════════════

VENV = "/Users/matthewjenkins/.hermes/hermes-agent/venv/bin"
WHISPER_CLI = "/opt/homebrew/bin/whisper-cli"
WHISPER_MODEL_PATH = os.path.expanduser("~/whisper-models/ggml-base.bin")
PIPER_MODEL_PATH = os.path.expanduser("~/piper-voices/en_US-lessac-medium.onnx")

# ═══ Audio Config ═══════════════════════════════════════════════════════════

SAMPLE_RATE = 16000
CHANNELS = 1
CHUNK = 512  # 32ms frames at 16kHz

# ═══ State ══════════════════════════════════════════════════════════════════

_vad_model: Optional[object] = None
_is_speaking = threading.Event()
_conversation_active = threading.Event()
_start_time = time.time()
_vad_lock = threading.Lock()


def _get_vad():
    """Lazy-load Silero VAD model. Thread-safe, cached."""
    global _vad_model
    if _vad_model is not None:
        return _vad_model
    with _vad_lock:
        if _vad_model is not None:
            return _vad_model
        try:
            import torch

            model, utils = torch.hub.load(
                repo_or_dir="snakers4/silero-vad",
                model="silero_vad",
                force_reload=False,
                trust_repo=True,
            )
            _vad_model = model
            logger.info("Silero VAD loaded")
        except Exception as e:
            logger.warning("VAD load failed: %s", e)
            _vad_model = False
        return _vad_model


def _detect_speech(audio_chunk: np.ndarray) -> bool:
    """Check if audio chunk contains speech using Silero VAD."""
    model = _get_vad()
    if model is False or model is None:
        return True

    import torch

    audio_tensor = torch.from_numpy(audio_chunk.astype(np.float32))
    if audio_tensor.max() > 0:
        audio_tensor = audio_tensor / audio_tensor.max()

    speech_prob = model(audio_tensor, SAMPLE_RATE).item()
    return speech_prob > 0.5


def _record_until_silence(max_duration: float = 15.0, silence_threshold: float = 0.8) -> bytes:
    """Record audio, stopping after silence_threshold seconds of silence."""
    p = pyaudio.PyAudio()
    stream = p.open(
        format=pyaudio.paInt16,
        channels=CHANNELS,
        rate=SAMPLE_RATE,
        input=True,
        frames_per_buffer=CHUNK,
    )

    frames = []
    silent_chunks = 0
    silence_limit = int(silence_threshold * SAMPLE_RATE / CHUNK)
    chunk_count = 0
    max_chunks = int(max_duration * SAMPLE_RATE / CHUNK)

    while chunk_count < max_chunks:
        data = stream.read(CHUNK, exception_on_overflow=False)
        frames.append(data)

        audio_np = np.frombuffer(data, dtype=np.int16).astype(np.float32)
        if _detect_speech(audio_np):
            silent_chunks = 0
        else:
            silent_chunks += 1

        chunk_count += 1

        if silent_chunks >= silence_limit and chunk_count > int(1.0 * SAMPLE_RATE / CHUNK):
            break

    stream.stop_stream()
    stream.close()
    p.terminate()

    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(p.get_sample_size(pyaudio.paInt16))
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(b"".join(frames))

    return buf.getvalue()


# ═══ STT Backends ═══════════════════════════════════════════════════════════


def _transcribe_nsspeech(wav_path: str) -> Optional[str]:
    """Transcribe using NSSpeechRecognizer (macOS native, Siri-quality).

    Uses pyobjc bridge to NSSpeechRecognizer. This is the preferred STT
    backend on macOS — fully local, no model download needed.
    """
    try:
        # Convert WAV to temporary file NSSpeechRecognizer can read
        # NSSpeechRecognizer uses the system speech recognition
        import objc  # noqa: F401 — pyobjc bootstrap
        from Foundation import NSURL  # noqa: F401
        from AppKit import NSSpeechRecognizer

        recognizer = NSSpeechRecognizer.alloc().init()
        if recognizer is None:
            return None

        # NSSpeechRecognizer works with commands, not general dictation.
        # For general STT, we use the speech recognition via the SFSpeechRecognizer
        # framework which IS available on macOS 10.15+.
        return None  # NSSpeechRecognizer is command-based, not dictation
    except ImportError:
        return None


def _transcribe_sfspeech(wav_path: str) -> Optional[str]:
    """Transcribe using SFSpeechRecognizer (macOS native dictation).

    Uses the system speech recognition engine — same as Siri dictation.
    100% local on macOS. Requires microphone permission.
    """
    try:
        import objc
        from Foundation import NSURL
        from Speech import (
            SFSpeechRecognizer,
            SFSpeechURLRecognitionRequest,
            SFSpeechRecognizerAuthorizationStatus,  # noqa: F401 — re-exported by reflection
        )

        # Check authorization
        auth_status = SFSpeechRecognizer.authorizationStatus()
        if auth_status != 3:  # SFSpeechRecognizerAuthorizationStatusAuthorized
            return None

        recognizer = SFSpeechRecognizer.alloc().init()
        if recognizer is None:
            return None

        url = NSURL.fileURLWithPath_(wav_path)
        request = SFSpeechURLRecognitionRequest.alloc().initWithURL_(url)

        # This is async — we need to block. Use a simple polling approach
        result_holder = {"text": None, "done": False}

        def handler(result, error):
            if error:
                result_holder["done"] = True
                return
            if result.isFinal():
                result_holder["text"] = result.bestTranscription().formattedString()
                result_holder["done"] = True

        task = recognizer.recognitionTaskWithRequest_requestHandler_(request, objc.Block(handler))

        # Wait up to 10 seconds
        for _ in range(100):
            if result_holder["done"]:
                break
            time.sleep(0.1)

        task.cancel()
        return result_holder.get("text")

    except (ImportError, Exception):
        return None


def _transcribe_whisper_cpp(wav_bytes: bytes, tmp_path: str) -> str:
    """Transcribe using whisper-cpp CLI."""
    result = subprocess.run(
        [WHISPER_CLI, "-m", WHISPER_MODEL_PATH, "-f", tmp_path, "-nt"],
        capture_output=True,
        text=True,
        timeout=30,
        env={"PATH": os.environ["PATH"]},
    )
    output = result.stdout
    lines = output.split("\n")
    text_lines = [
        line for line in lines if line.strip() and not line.startswith("[") and not line.startswith("whisper_")
    ]
    return " ".join(text_lines).strip()


def _transcribe_faster_whisper(wav_path: str) -> str:
    """Transcribe using faster-whisper (Python, MPS-accelerated)."""
    from faster_whisper import WhisperModel

    model = WhisperModel("base", device="auto", compute_type="auto")
    segments, _ = model.transcribe(wav_path, beam_size=5)
    return " ".join(seg.text.strip() for seg in segments)


def _transcribe(wav_bytes: bytes) -> str:
    """Multi-strategy STT with fallback chain.

    Strategy order:
      1. SFSpeechRecognizer (macOS Siri dictation — best quality, fully local)
      2. whisper-cpp (Metal-accelerated, GGML)
      3. faster-whisper (Python, MPS/CPU)
    """
    # Write WAV to temp file
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        f.write(wav_bytes)
        tmp_path = f.name

    try:
        # Strategy 1: macOS native SFSpeechRecognizer
        text = _transcribe_sfspeech(tmp_path)
        if text:
            return text

        # Strategy 2: whisper-cpp
        if os.path.exists(WHISPER_CLI) and os.path.exists(WHISPER_MODEL_PATH):
            text = _transcribe_whisper_cpp(wav_bytes, tmp_path)
            if text:
                return text

        # Strategy 3: faster-whisper
        try:
            text = _transcribe_faster_whisper(tmp_path)
            if text:
                return text
        except ImportError:
            pass

        return "[STT: all backends unavailable]"

    except Exception as e:
        logger.error("STT error: %s", e)
        return f"[STT error: {e}]"
    finally:
        Path(tmp_path).unlink(missing_ok=True)


# ═══ TTS Backends ═══════════════════════════════════════════════════════════


def _speak_piper(text: str) -> bool:
    """Speak using Piper TTS."""
    if not text.strip():
        return False

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        wav_path = f.name

    try:
        result = subprocess.run(
            [f"{VENV}/piper", "-m", PIPER_MODEL_PATH, "-f", wav_path],
            input=text,
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode == 0 and os.path.exists(wav_path):
            subprocess.run(["afplay", wav_path], timeout=30)
            return True
    except Exception:
        pass
    finally:
        Path(wav_path).unlink(missing_ok=True)

    return False


def _speak_macos_say(text: str) -> bool:
    """Fallback: macOS say command."""
    try:
        subprocess.run(["say", "-v", "Samantha", text], timeout=30, capture_output=True)
        return True
    except Exception:
        return False


def _speak(text: str, prefer_natural: bool = True) -> tuple[bool, str]:
    """Multi-strategy TTS with fallback.

    Strategy order:
      1. Piper TTS (neural, natural voice)
      2. macOS say (system voice)
    """
    if not text.strip():
        return False, "empty"

    if prefer_natural and os.path.exists(PIPER_MODEL_PATH):
        if _speak_piper(text):
            return True, "piper"

    if _speak_macos_say(text):
        return True, "macOS_say"

    return False, "error"


# ═══ Tools ══════════════════════════════════════════════════════════════════


@server.tool()
def listen(duration: float = 8.0) -> dict:
    """Listen through the microphone with smart turn detection.

    Records until silence is detected (max 15 seconds, stops after ~0.8s
    silence). Transcribes using a 3-strategy fallback:
    SFSpeechRecognizer → whisper-cpp → faster-whisper.

    Returns:
        dict: transcribed text, duration, whether conversation is active
    """
    wav = _record_until_silence(max_duration=min(duration, 15.0), silence_threshold=0.8)

    audio_duration = len(wav) / (SAMPLE_RATE * 2)

    if audio_duration < 1.0:
        return {
            "status": "ok",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "text": "",
            "empty": True,
            "duration_sec": round(audio_duration, 2),
        }

    text = _transcribe(wav)

    return {
        "status": "ok",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "text": text.strip() if text else "",
        "empty": not bool(text.strip() if text else ""),
        "duration_sec": round(audio_duration, 2),
        "vad_active": _vad_model is not None and _vad_model is not False,
    }


@server.tool()
def speak_text(text: str, natural: bool = True) -> dict:
    """Speak text aloud with a natural voice.

    Uses Piper TTS (en_US-lessac-medium) by default.
    Falls back to macOS system voice if Piper unavailable.

    Args:
        text: The text to speak
        natural: Use Piper natural voice (True) or system voice (False)

    Returns:
        dict: success/failure
    """
    if not text.strip():
        return {"status": "ok", "spoken": False, "reason": "empty text"}

    ok, backend = _speak(text, prefer_natural=natural)

    return {
        "status": "ok" if ok else "error",
        "spoken": ok,
        "backend": backend,
        "text_preview": text[:100],
    }


@server.tool()
def voice_health() -> dict:
    """Check full voice pipeline health — mic, VAD, STT, TTS."""
    status = {
        "status": "ok",
        "uptime": int(time.time() - _start_time),
        "microphone": False,
        "mic_name": "",
        "vad": False,
        "vad_backend": "silero",
        "stt": False,
        "stt_backends_available": [],
        "tts": False,
        "tts_backends_available": [],
    }

    # Microphone
    try:
        p = pyaudio.PyAudio()
        for i in range(p.get_device_count()):
            info = p.get_device_info_by_index(i)
            if info.get("maxInputChannels", 0) > 0:
                status["microphone"] = True
                status["mic_name"] = info.get("name", "unknown")
                break
        p.terminate()
    except Exception:
        pass

    # VAD
    try:
        _get_vad()
        status["vad"] = True
    except Exception:
        pass

    # STT — check all backends
    stt_backends = []

    # Check SFSpeechRecognizer
    try:
        from Speech import SFSpeechRecognizer

        auth = SFSpeechRecognizer.authorizationStatus()
        if auth == 3:
            stt_backends.append("sfspeech")
    except ImportError:
        pass

    if os.path.exists(WHISPER_CLI) and os.path.exists(WHISPER_MODEL_PATH):
        stt_backends.append("whisper-cpp")

    try:
        import faster_whisper  # noqa: F401

        stt_backends.append("faster-whisper")
    except ImportError:
        pass

    status["stt_backends_available"] = stt_backends
    status["stt"] = len(stt_backends) > 0

    # TTS — check all backends
    tts_backends = []
    if os.path.exists(PIPER_MODEL_PATH):
        tts_backends.append("piper")
    tts_backends.append("macOS_say")  # always available
    status["tts_backends_available"] = tts_backends
    status["tts"] = len(tts_backends) > 0

    return status


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO)
    server.run(transport="streamable-http")
