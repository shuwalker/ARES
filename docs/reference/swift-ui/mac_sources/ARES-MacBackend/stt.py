#!/usr/bin/env python3
"""Whisper speech-to-text for ARES-Mac."""
import logging
import tempfile
from pathlib import Path

logger = logging.getLogger("ares.stt")

class SpeechTranscriber:
    """Transcribes speech to text using OpenAI Whisper."""
    
    def __init__(self, model_size="base"):
        self._model = None
        self._model_size = model_size
    
    def _load_model(self):
        if self._model is None:
            import whisper
            logger.info(f"Loading Whisper model '{self._model_size}'...")
            self._model = whisper.load_model(self._model_size)
            logger.info("Whisper model loaded")
    
    def transcribe_file(self, audio_path: Path) -> str:
        """Transcribe an audio file to text."""
        self._load_model()
        result = self._model.transcribe(str(audio_path))
        return result["text"].strip()
    
    def transcribe_from_mic(self, duration: float = 5.0) -> str:
        """Record from mic and transcribe."""
        try:
            import pyaudio
            import wave
            import numpy as np
            
            FORMAT = pyaudio.paInt16
            CHANNELS = 1
            RATE = 16000
            CHUNK = 1024
            
            audio = pyaudio.PyAudio()
            stream = audio.open(
                format=FORMAT,
                channels=CHANNELS,
                rate=RATE,
                input=True,
                frames_per_buffer=CHUNK
            )
            
            logger.info(f"Recording for {duration}s...")
            frames = []
            for _ in range(0, int(RATE / CHUNK * duration)):
                data = stream.read(CHUNK)
                frames.append(data)
            
            stream.stop_stream()
            stream.close()
            audio.terminate()
            
            # Save to temp file
            tmp = Path(tempfile.mktemp(suffix=".wav"))
            with wave.open(str(tmp), "wb") as wf:
                wf.setnchannels(CHANNELS)
                wf.setsampwidth(audio.get_sample_size(FORMAT))
                wf.setframerate(RATE)
                wf.writeframes(b"".join(frames))
            
            text = self.transcribe_file(tmp)
            tmp.unlink(missing_ok=True)
            return text
            
        except ImportError:
            logger.error("pyaudio not installed. pip install pyaudio")
            return ""
        except Exception as e:
            logger.error(f"Mic transcription error: {e}")
            return ""
