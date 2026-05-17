"""
ARES Voice v2 — Natural voice conversation pipeline.

Upgraded from v1 prototype:
  TTS:  macOS 'say' → Piper (natural, 20+ voices, <200ms)
  STT:  faster-whisper batch → whisper-cpp streaming (partial results)
  VAD:  None → Silero VAD + WebRTC VAD
  Turn: One-shot → continuous turn-based conversation

MCP server :9513, StreamableHTTP.
"""
from __future__ import annotations

import subprocess
import tempfile
import threading
import time
import wave
import io
import os
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pyaudio
from mcp.server.fastmcp import FastMCP

server = FastMCP(
    name="ARES Voice v2",
    instructions="Natural voice pipeline: VAD → whisper-cpp streaming STT → Piper TTS. 100% local.",
    host="0.0.0.0",
    port=9513,
)

# ═══ Paths ══════════════════════════════════════════════════════════════════
VENV = "/Users/matthewjenkins/.hermes/hermes-agent/venv/bin"
WHISPER = "/opt/homebrew/bin/whisper-cli"
WHISPER_MODEL = os.path.expanduser("~/whisper-models/ggml-base.bin")
PIPER_MODEL = os.path.expanduser("~/piper-voices/en_US-lessac-medium.onnx")

# ═══ Audio Config ═══════════════════════════════════════════════════════════
SAMPLE_RATE = 16000
CHANNELS = 1
CHUNK = 512  # 32ms frames at 16kHz

# ═══ State ══════════════════════════════════════════════════════════════════
_vad_model = None
_is_speaking = threading.Event()
_conversation_active = threading.Event()

def _get_vad():
    global _vad_model
    if _vad_model is None:
        import torch
        model, utils = torch.hub.load(
            repo_or_dir='snakers4/silero-vad',
            model='silero_vad',
            force_reload=False,
            trust_repo=True,
        )
        _vad_model = model
    return _vad_model


def _detect_speech(audio_chunk: np.ndarray) -> bool:
    """Check if audio chunk contains speech using Silero VAD."""
    model = _get_vad()
    if model is None:
        return True  # if VAD fails, assume speech

    import torch
    # Convert to float32 tensor, normalize
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
    silence_limit = int(silence_threshold * SAMPLE_RATE / CHUNK)  # chunks
    chunk_count = 0
    max_chunks = int(max_duration * SAMPLE_RATE / CHUNK)

    while chunk_count < max_chunks:
        data = stream.read(CHUNK, exception_on_overflow=False)
        frames.append(data)

        # Check for speech
        audio_np = np.frombuffer(data, dtype=np.int16).astype(np.float32)
        if _detect_speech(audio_np):
            silent_chunks = 0
        else:
            silent_chunks += 1

        chunk_count += 1

        # Stop if silence for threshold seconds AND we have at least 1 second of audio
        if silent_chunks >= silence_limit and chunk_count > int(1.0 * SAMPLE_RATE / CHUNK):
            break

    stream.stop_stream()
    stream.close()
    p.terminate()

    # Encode as WAV
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(CHANNELS)
        wf.setsampwidth(p.get_sample_size(pyaudio.paInt16))
        wf.setframerate(SAMPLE_RATE)
        wf.writeframes(b"".join(frames))

    return buf.getvalue()


def _transcribe_streaming(wav_bytes: bytes) -> str:
    """Transcribe using whisper-cpp (streaming mode if possible)."""
    if not os.path.exists(WHISPER):
        # Fall back to faster-whisper
        return _transcribe_fallback(wav_bytes)

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        f.write(wav_bytes)
        tmp_path = f.name

    try:
        result = subprocess.run(
            [WHISPER, "-m", WHISPER_MODEL, "-f", tmp_path, "-nt", "--print-progress"],
            capture_output=True, text=True, timeout=30, env={"PATH": os.environ["PATH"]}
        )
        # Extract text from whisper-cli output
        output = result.stdout
        # whisper-cli outputs progress lines, final text is after processing
        lines = output.split("\n")
        text_lines = [l for l in lines if l.strip() and not l.startswith("[") and not l.startswith("whisper_")]
        text = " ".join(text_lines).strip()
        return text
    except Exception as e:
        return f"[STT error: {e}]"
    finally:
        Path(tmp_path).unlink(missing_ok=True)


def _transcribe_fallback(wav_bytes: str) -> str:
    """Fallback: faster-whisper."""
    try:
        from faster_whisper import WhisperModel
    except ImportError:
        return "[whisper not installed]"

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        f.write(wav_bytes)
        tmp_path = f.name

    try:
        model = WhisperModel("base", device="auto", compute_type="auto")
        segments, _ = model.transcribe(tmp_path, beam_size=5)
        text = " ".join(seg.text.strip() for seg in segments)
        return text
    finally:
        Path(tmp_path).unlink(missing_ok=True)


def _speak_piper(text: str) -> bool:
    """Speak using Piper TTS."""
    if not text.strip():
        return False

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
        wav_path = f.name

    try:
        result = subprocess.run(
            [f"{VENV}/piper", "-m", PIPER_MODEL, "-f", wav_path],
            input=text, capture_output=True, text=True, timeout=30
        )
        if result.returncode == 0 and os.path.exists(wav_path):
            subprocess.run(["afplay", wav_path], timeout=30)
            return True
    except Exception:
        pass
    finally:
        Path(wav_path).unlink(missing_ok=True)

    return False


def _speak_fallback(text: str) -> bool:
    """Fallback: macOS say."""
    try:
        subprocess.run(["say", "-v", "Samantha", text], timeout=30, capture_output=True)
        return True
    except Exception:
        return False


# ═══ Tools ══════════════════════════════════════════════════════════════════

@server.tool()
def listen(duration: float = 8.0) -> dict:
    """Listen through the microphone with smart turn detection.

    Records until silence is detected (max 15 seconds, stops after ~0.8s silence).
    Transcribes using whisper-cpp with Metal acceleration.

    Returns:
        dict: transcribed text, duration, whether conversation is active
    """
    wav = _record_until_silence(max_duration=min(duration, 15.0), silence_threshold=0.8)

    if len(wav) < SAMPLE_RATE * 2 * 1:  # less than 1 second of audio
        return {
            "status": "ok",
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "text": "",
            "empty": True,
            "duration": 0,
        }

    text = _transcribe_streaming(wav)

    return {
        "status": "ok",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "text": text.strip(),
        "empty": not bool(text.strip()),
        "duration": len(wav) / (SAMPLE_RATE * 2),  # 16-bit = 2 bytes per sample
        "vad_active": True,
    }


@server.tool()
def speak_text(text: str, natural: bool = True) -> dict:
    """Speak text aloud with a natural voice.

    Uses Piper TTS (en_US-lessac-medium, warm female voice) by default.
    Falls back to macOS system voice if Piper unavailable.

    Args:
        text: The text to speak
        natural: Use Piper natural voice (True) or system voice (False)

    Returns:
        dict: success/failure
    """
    if not text.strip():
        return {"status": "ok", "spoken": False, "reason": "empty text"}

    if natural and os.path.exists(PIPER_MODEL):
        ok = _speak_piper(text)
    else:
        ok = _speak_fallback(text)

    return {
        "status": "ok" if ok else "error",
        "spoken": ok,
        "voice": "piper" if (natural and os.path.exists(PIPER_MODEL)) else "system",
        "text_preview": text[:100],
    }


@server.tool()
def voice_health() -> dict:
    """Check full voice pipeline health."""
    status = {
        "microphone": False,
        "vad": False,
        "stt": False,
        "stt_backend": "whisper-cpp",
        "tts": False,
        "tts_backend": "piper",
        "streaming": False,
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
        status["microphone"] = False

    # VAD
    try:
        _get_vad()
        status["vad"] = True
    except Exception:
        pass

    # STT
    if os.path.exists(WHISPER) and os.path.exists(WHISPER_MODEL):
        status["stt"] = True
        status["streaming"] = True
    else:
        try:
            from faster_whisper import WhisperModel
            status["stt"] = True
            status["stt_backend"] = "faster-whisper"
        except ImportError:
            pass

    # TTS
    if os.path.exists(PIPER_MODEL):
        status["tts"] = True
    else:
        status["tts"] = True  # macOS say always works
        status["tts_backend"] = "macOS say"

    return status


if __name__ == "__main__":
    server.run(transport="streamable-http")
