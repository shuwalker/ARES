#!/usr/bin/env python3
"""
Real-time STT using pywhispercpp + webrtcvad for live transcription on macOS.
"""

import asyncio
import logging
from collections.abc import Callable

import numpy as np
import pyaudio
import webrtcvad
from pywhispercpp.model import Model


class PyWhisperCPPSTTRunner:
    """Live STT runner using pywhispercpp and webrtcvad."""

    def __init__(self, config: dict):
        self.logger = logging.getLogger(__name__)
        self.model_name = config.get("model", "tiny.en")
        self.sample_rate = config.get("sample_rate", 16000)
        self.chunk_size = config.get("chunk_size", 480)

        self.model = Model(self.model_name, print_realtime=True)
        self.vad = webrtcvad.Vad(2)
        self.pa = pyaudio.PyAudio()
        self.stream = None
        self.transcript_callback: Callable | None = None
        self.running = False
        self.buffer = bytearray()

    def set_transcript_callback(self, callback: Callable):
        """Set callback for final transcripts."""
        self.transcript_callback = callback
        self.logger.info("✅ Transcript callback set")

    async def start(self):
        """Start mic stream and processing loop."""
        try:
            self.logger.info(f"📥 Loading model: {self.model_name}")
            self.stream = self.pa.open(
                format=pyaudio.paInt16,
                channels=1,
                rate=self.sample_rate,
                input=True,
                frames_per_buffer=self.chunk_size,
            )
            self.running = True
            asyncio.create_task(self._run_loop())
            self.logger.info("✅ PyWhisperCPPSTTRunner started")
            return True
        except Exception as e:
            self.logger.error(f"❌ Failed to start PyWhisperCPPSTTRunner: {e}")
            return False

    async def _run_loop(self):
        """Microphone streaming + VAD loop."""
        while self.running:
            try:
                if not self.stream:
                    self.logger.warning("⚠️ Audio stream is not initialized.")
                    await asyncio.sleep(0.5)
                    continue

                data = self.stream.read(self.chunk_size, exception_on_overflow=False)

                # Check if we have valid audio data
                if len(data) == 0:
                    continue

                # Ensure we have enough data for VAD (30ms at 16kHz = 480 bytes)
                if len(data) >= 480:
                    try:
                        if self.vad.is_speech(data, sample_rate=self.sample_rate):
                            self.buffer.extend(data)
                        elif self.buffer and len(self.buffer) > int(
                            self.sample_rate * 0.5
                        ):  # 0.5s of audio
                            audio = np.frombuffer(self.buffer, dtype=np.int16)
                            self.buffer.clear()
                            try:
                                self.model.transcribe(
                                    audio, new_segment_callback=self._on_segment
                                )
                            except Exception as transcribe_error:
                                self.logger.error(
                                    f"❌ Transcription error: {transcribe_error}"
                                )
                                self.buffer.clear()
                    except Exception as vad_error:
                        self.logger.error(f"❌ VAD error: {vad_error}")
                        continue

            except Exception as e:
                self.logger.error(f"❌ Error in audio loop: {e}")
                await asyncio.sleep(0.1)
                continue
            await asyncio.sleep(0.01)

    def _on_segment(self, segment):
        text = segment.text.strip()
        if text and self.transcript_callback:
            self.logger.info(f"🎤 Transcript: {text}")
            self.transcript_callback(text, True)

    async def stop(self):
        """Stop mic and release resources."""
        self.running = False
        if self.stream:
            self.stream.stop_stream()
            self.stream.close()
        self.pa.terminate()
        self.logger.info("🛑 PyWhisperCPPSTTRunner stopped")

    def get_status(self):
        return {
            "running": self.running,
            "model": self.model_name,
            "sample_rate": self.sample_rate,
        }


# CLI test
if __name__ == "__main__":
    import sys
    from pathlib import Path

    # Add project root to path
    project_root = Path(__file__).parent.parent
    sys.path.insert(0, str(project_root))

    from extensions.llm.llm_ollama_mistral import OllamaMistralRunner
    from extensions.audio.tts_kokoro import KokoroTTSRunner

    def on_transcript(text, is_final):
        print(f"\n🎤 TRANSCRIPT: '{text}' (final: {is_final})")

    async def main():
        print("🤖 AI Assistant CLI with whispercpp STT")
        print("=" * 50)

        # Initialize STT
        stt_config = {
            "model": "tiny.en",
            "sample_rate": 16000,
            "chunk_size": 1024,
        }

        stt = PyWhisperCPPSTTRunner(stt_config)
        stt.set_transcript_callback(on_transcript)

        # Initialize LLM
        llm_config = {
            "model": "mistral:latest",
            "temperature": 0.7,
            "max_tokens": 1000,
        }

        llm = OllamaMistralRunner(llm_config)

        # Initialize TTS
        tts_config = {
            "kokoro_voice": "af_heart",
            "kokoro_lang_code": "a",
            "sample_rate": 24000,
            "channels": 1,
            "kokoro_device": "cpu",
        }

        tts = KokoroTTSRunner(tts_config)

        print("🚀 Starting AI Assistant...")

        # Start all components
        if not await stt.start():
            print("❌ Failed to start STT")
            return

        if not await llm.start():
            print("❌ Failed to start LLM")
            await stt.stop()
            return

        if not await tts.start():
            print("❌ Failed to start TTS")
            await stt.stop()
            await llm.stop()
            return

        print("✅ AI Assistant started successfully!")
        print("🎤 Speak into your microphone to chat with the AI")
        print("Press Ctrl+C to stop")
        print("-" * 50)

        # Simple conversation loop
        conversation_history = []

        def on_transcript_with_ai(text, is_final):
            if is_final and text.strip():
                print(f"\n🎤 You said: {text}")
                asyncio.create_task(process_user_input(text))

        async def process_user_input(text):
            try:
                # Generate AI response
                print("🧠 AI is thinking...")
                response = await llm.generate_response(text)
                print(f"🤖 AI: {response}")

                # Speak the response
                print("🔊 Speaking response...")
                await tts.synthesize(response)

                # Add to conversation history
                conversation_history.append({"user": text, "ai": response})

            except Exception as e:
                print(f"❌ Error processing input: {e}")

        # Set the callback
        stt.set_transcript_callback(on_transcript_with_ai)

        try:
            while True:
                await asyncio.sleep(0.1)
        except KeyboardInterrupt:
            print("\n🛑 Stopping AI Assistant...")
            await stt.stop()
            await llm.stop()
            await tts.stop()
            print("✅ AI Assistant stopped")

    asyncio.run(main())
