"""Environment detection — desktop by default, robot when explicitly set.

Layer 1 (Cognition) — portable. No platform imports.
"""

import os
from typing import Literal

Environment = Literal["desktop", "robot"]


def detect_environment() -> Environment:
    """Detect runtime environment. 
    
    Returns 'desktop' by default. Set LILITH_ENVIRONMENT=robot to flip.
    Invalid values raise ValueError — being in a body is a deliberate decision.
    """
    env = os.environ.get("LILITH_ENVIRONMENT", "desktop")
    if env not in ("desktop", "robot"):
        raise ValueError(f"Invalid LILITH_ENVIRONMENT: {env}. Must be 'desktop' or 'robot'.")
    return env  # type: ignore


def is_body_present() -> bool:
    """True if running inside a robot body (JP01 future)."""
    return detect_environment() == "robot"
