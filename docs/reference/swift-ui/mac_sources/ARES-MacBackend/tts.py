#!/usr/bin/env python3
"""Coqui TTS voice output for ARES-Mac."""
import logging
import tempfile
from pathlib import Path
import urllib.request
import json

logger = logging.getLogger("ares.tts")

# Coqui TTS server running on RackPC
TTS_SERVER_URL = "http://10.15.0.239:8002/tts/speak"

# Fallback: Mac local TTS
import subprocess

class TextToSpeech:
    """Speaks text using the Coqui TTS server or macOS say command."""
    
    def speak(self, text: str) -> Path:
        """Convert text to speech and save to temp file. Returns audio path."""
        # Try Coqui server first
        audio_path = self._try_coqui(text)
        if audio_path:
            return audio_path
        
        # Fallback to macOS say command
        return self._say_fallback(text)
    
    def _try_coqui(self, text: str) -> Path:
        """Try the Coqui TTS server on RackPC."""
        try:
            data = json.dumps({"text": text}).encode()
            req = urllib.request.Request(
                TTS_SERVER_URL,
                data=data,
                headers={"Content-Type": "application/json"}
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                tmp = Path(tempfile.mktemp(suffix=".wav"))
                tmp.write_bytes(resp.read())
                logger.info(f"Coqui TTS response saved to {tmp}")
                return tmp
        except Exception as e:
            logger.warn(f"Coqui TTS unavailable: {e}")
            return None
    
    def _say_fallback(self, text: str) -> Path:
        """Fallback to macOS say command for local TTS."""
        try:
            tmp = Path(tempfile.mktemp(suffix=".aiff"))
            subprocess.run(
                ["say", "-o", str(tmp), text],
                capture_output=True,
                timeout=30
            )
            logger.info(f"macOS say fallback: {tmp}")
            return tmp
        except Exception as e:
            logger.error(f"TTS fallback failed: {e}")
            return None
