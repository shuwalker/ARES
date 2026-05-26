#!/usr/bin/env python3
"""Experience logging for ARES-Mac — records interactions for training."""
import json
import time
from pathlib import Path

HOME = Path.home()
EXPERIENCE_LOG = HOME / ".ares" / "experience.jsonl"

def _ensure_log():
    EXPERIENCE_LOG.parent.mkdir(parents=True, exist_ok=True)

class ExperienceLogger:
    """Logs each interaction as JSONL for later training."""
    
    def log_interaction(self, query: str, response: str, duration_ms: int = 0):
        _ensure_log()
        entry = {
            "timestamp": time.time(),
            "iso_time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "query": query,
            "response_length": len(response),
            "duration_ms": duration_ms,
        }
        with open(EXPERIENCE_LOG, "a") as f:
            f.write(json.dumps(entry) + "\n")
    
    def log_state_change(self, from_state: str, to_state: str):
        _ensure_log()
        entry = {
            "timestamp": time.time(),
            "iso_time": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "event": "state_change",
            "from_state": from_state,
            "to_state": to_state,
        }
        with open(EXPERIENCE_LOG, "a") as f:
            f.write(json.dumps(entry) + "\n")
    
    def get_recent(self, count: int = 10) -> list:
        if not EXPERIENCE_LOG.exists():
            return []
        with open(EXPERIENCE_LOG) as f:
            lines = f.readlines()
        return [json.loads(l) for l in lines[-count:]]

logger = ExperienceLogger()
