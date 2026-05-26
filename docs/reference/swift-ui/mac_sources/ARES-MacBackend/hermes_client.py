#!/usr/bin/env python3
"""Hermes agent client — queries Hermes CLI for responses."""
import logging
import subprocess
import shlex
from pathlib import Path

logger = logging.getLogger("ares.hermes")

HOME = Path.home()
HERMES_BIN = HOME / ".local/bin/hermes"

class HermesClient:
    """Communicates with the Hermes agent via CLI."""
    
    def query(self, text: str, profile: str = "assistant") -> str:
        """Send a query to Hermes and return the response."""
        if not HERMES_BIN.exists():
            logger.error(f"Hermes not found at {HERMES_BIN}")
            return "I'm not connected to my agent core yet."
        
        try:
            result = subprocess.run(
                [
                    str(HERMES_BIN),
                    "-p", profile,
                    "-z", text,
                    "--no-stream"
                ],
                capture_output=True,
                text=True,
                timeout=120,
                env={
                    "PATH": f"{HOME}/.local/bin:{HOME}/.hermes/hermes-agent/venv/bin:/usr/local/bin:/usr/bin:/bin",
                    "HOME": str(HOME),
                }
            )
            
            if result.returncode == 0 and result.stdout.strip():
                response = result.stdout.strip()
                logger.info(f"Hermes response ({len(response)} chars)")
                return response
            else:
                logger.warn(f"Hermes returned empty or error: {result.stderr[:200]}")
                return self._fallback_response(text)
                
        except subprocess.TimeoutExpired:
            logger.error("Hermes query timed out (120s)")
            return "I was thinking about that but it's taking a while. Can you ask again?"
        except Exception as e:
            logger.error(f"Hermes query failed: {e}")
            return self._fallback_response(text)
    
    def _fallback_response(self, text: str) -> str:
        """Simple fallback when Hermes is unavailable."""
        text_lower = text.lower()
        
        if "schedule" in text_lower or "calendar" in text_lower or "day" in text_lower:
            return "I can check your calendar but I need Hermes connected to do it properly. Try again in a moment."
        elif "hello" in text_lower or "hi" in text_lower or "hey" in text_lower:
            return "Hey Matthew. I'm here. Just warming up my agent connection."
        elif "who" in text_lower or "are you" in text_lower:
            return "I'm ARES-Mac. Your persistent desk companion. Still getting my core connected."
        else:
            return f"I heard you ask about '{text[:50]}...' but I'm still connecting to my agent backend. Give me a moment."
