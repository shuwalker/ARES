#!/usr/bin/env python3
"""
Simplified Kokoro TTS Runner

A clean, simple TTS module using Kokoro for text-to-speech synthesis.
"""

import asyncio
import logging
import sys
from pathlib import Path

import numpy as np
import sounddevice as sd

# Add project root to path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))

# Import kokoro
try:
    from kokoro import KPipeline

    KOKORO_AVAILABLE = True
except ImportError:
    KOKORO_AVAILABLE = False
    print("Warning: kokoro package not available. Install with: pip install kokoro")

try:
    import sounddevice  # noqa: F401

    SOUNDDEVICE_AVAILABLE = True
except ImportError:
    SOUNDDEVICE_AVAILABLE = False
    print("Warning: sounddevice package not available. Audio playback will be disabled.")


class KokoroTTSRunner:
    """Simplified Kokoro TTS runner."""

    def __init__(self, config: dict):
        self.logger = logging.getLogger(__name__)

        # Configuration
        self.voice = config.get("kokoro_voice", "af_heart")
        self.lang_code = config.get("kokoro_lang_code", "a")
        self.device = config.get("kokoro_device", "cpu")

        # State
        self.is_running = False
        self.pipeline = None

        self.logger.info("🔧 Kokoro TTS runner initialized")

    async def start(self) -> bool:
        """Start the TTS runner."""
        if self.is_running:
            return True

        try:
            self.logger.info("🚀 Starting Kokoro TTS runner...")

            if not KOKORO_AVAILABLE:
                self.logger.error("❌ Kokoro package not available")
                return False

            # Initialize pipeline
            import warnings

            with warnings.catch_warnings():
                warnings.filterwarnings("ignore")
                self.pipeline = KPipeline(lang_code=self.lang_code, device=self.device)

            self.is_running = True
            self.logger.info(f"✅ Kokoro TTS started with voice: {self.voice}")
            return True

        except Exception as e:
            self.logger.error(f"❌ Failed to start Kokoro TTS: {e}")
            return False

    async def stop(self):
        """Stop the TTS runner."""
        if not self.is_running:
            return

        self.logger.info("🛑 Stopping Kokoro TTS runner...")
        self.is_running = False

        if self.pipeline:
            self.pipeline = None

        self.logger.info("✅ Kokoro TTS stopped")

    async def synthesize(self, text: str) -> bool:
        """Synthesize and play text."""
        if not self.is_running or not self.pipeline:
            self.logger.warning("⚠️ TTS not running")
            return False

        try:
            self.logger.info(f"🔊 Speaking: {text[:50]}...")

            # Synthesize audio
            audio_data = await self._synthesize_text(text)
            if audio_data is not None:
                # Simple audio playback
                # (you can replace this with your preferred method)
                self._play_audio(audio_data)
                self.logger.info("✅ Speech completed")
                return True
            else:
                self.logger.error("❌ Audio synthesis failed")
                return False

        except Exception as e:
            self.logger.error(f"❌ Synthesis error: {e}")
            return False

    async def _synthesize_text(self, text: str) -> np.ndarray | None:
        """Synthesize text to audio."""
        try:
            if not self.pipeline:
                return None

            # Run synthesis in executor to avoid blocking
            loop = asyncio.get_event_loop()
            result = await loop.run_in_executor(None, self._synthesize_sync, text)
            return result

        except Exception as e:
            self.logger.error(f"❌ Synthesis error: {e}")
            return None

    def _synthesize_sync(self, text: str) -> np.ndarray | None:
        """Synchronous synthesis."""
        try:
            import warnings

            with warnings.catch_warnings():
                warnings.filterwarnings("ignore")

                # Use Kokoro pipeline
                if self.pipeline is None:
                    return None
                generator = self.pipeline(text, voice=self.voice)
                audio_segments = []

                for gs, ps, audio in generator:
                    if audio is not None:
                        audio_segments.append(audio)

                if audio_segments:
                    full_audio = np.concatenate(audio_segments)
                    self.logger.info(f"✅ Synthesized {len(full_audio)} samples")
                    return full_audio.astype(np.float32)
                else:
                    self.logger.warning("⚠️ No audio generated")
                    return None

        except Exception as e:
            self.logger.error(f"❌ Sync synthesis error: {e}")
            return None

    def _play_audio(self, audio_data: np.ndarray):
        """Simple audio playback using sounddevice."""
        try:
            audio_int16 = (audio_data * 32767).astype(np.int16)
            self.logger.info(f"🔊 Playing {len(audio_int16)} samples")
            sd.play(audio_int16, samplerate=22050, blocking=True)
        except Exception as e:
            self.logger.error(f"❌ Audio playback error: {e}")

    def get_status(self) -> dict:
        """Get runner status."""
        return {
            "is_running": self.is_running,
            "voice": self.voice,
            "pipeline_ready": self.pipeline is not None,
        }

    async def speak(self, text: str) -> bool:
        """Alias for synthesize."""
        return await self.synthesize(text)


# Simple test function
async def test_kokoro():
    """Test the Kokoro TTS runner."""
    config = {
        "kokoro_voice": "af_heart",
        "kokoro_lang_code": "a",
        "kokoro_device": "cpu",
    }

    runner = KokoroTTSRunner(config)

    if await runner.start():
        await runner.synthesize("Hello, this is a test of the Kokoro TTS system.")
        await runner.stop()


if __name__ == "__main__":
    asyncio.run(test_kokoro())
