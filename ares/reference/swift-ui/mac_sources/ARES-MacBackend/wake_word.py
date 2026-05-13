#!/usr/bin/env python3
"""openWakeWord wake word listener for ARES-Mac."""
import logging
import threading
from pathlib import Path

logger = logging.getLogger("ares.wakeword")

class WakeWordListener:
    """Listens for "ARES" wake word using openWakeWord."""
    
    def __init__(self, on_wake=None, model_path=None):
        self.on_wake = on_wake
        self.running = False
        self._thread = None
        self._model = None
        self._model_path = model_path
    
    def start(self):
        """Start listening for wake word in background thread."""
        self.running = True
        self._thread = threading.Thread(target=self._listen_loop, daemon=True)
        self._thread.start()
        logger.info("Wake word listener started")
    
    def stop(self):
        """Stop listening."""
        self.running = False
        logger.info("Wake word listener stopped")
    
    def _listen_loop(self):
        try:
            from openwakeword import Model
            import pyaudio
            import numpy as np
            
            # Load model
            self._model = Model(
                wakeword_models=["ares"],
                model_path=self._model_path
            )
            
            # Audio stream
            FORMAT = pyaudio.paInt16
            CHANNELS = 1
            RATE = 16000
            CHUNK = 1280
            
            audio = pyaudio.PyAudio()
            stream = audio.open(
                format=FORMAT,
                channels=CHANNELS,
                rate=RATE,
                input=True,
                frames_per_buffer=CHUNK
            )
            
            logger.info("Mic stream open, listening for 'ARES'...")
            
            while self.running:
                audio_data = np.frombuffer(
                    stream.read(CHUNK, exception_on_overflow=False),
                    dtype=np.int16
                )
                prediction = self._model.predict(audio_data)
                
                if prediction.get("ares", 0) > 0.5:
                    logger.info("Wake word 'ARES' detected!")
                    if self.on_wake:
                        self.on_wake()
            
            stream.stop_stream()
            stream.close()
            audio.terminate()
            
        except ImportError as e:
            logger.error(f"openWakeWord not installed: {e}")
            logger.error("Run: pip install openwakeword pyaudio")
        except Exception as e:
            logger.error(f"Wake word error: {e}")
            self.running = False
