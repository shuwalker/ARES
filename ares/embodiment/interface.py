"""ARES embodiment interface — abstract protocol for platform-specific I/O.

Skills never import platform APIs directly. They call this interface.
The embodiment layer resolves the call differently on desktop vs robot.
"""

from __future__ import annotations

from abc import ABC, abstractmethod


class Embodiment(ABC):
    """Abstract embodiment — platform I/O lives here, not in skills."""

    @abstractmethod
    def send_text(self, text: str) -> None:
        """Display text to the user (screen, speaker, etc.)."""
        ...

    @abstractmethod
    def capture_image(self) -> bytes | None:
        """Capture a frame from the primary camera. Returns None if no camera."""
        ...

    @abstractmethod
    def capture_audio(self, duration_seconds: float) -> bytes | None:
        """Capture audio from the primary mic. Returns None if no mic."""
        ...

    @abstractmethod
    def play_audio(self, audio: bytes) -> None:
        """Play audio through the primary speaker."""
        ...

    @abstractmethod
    def get_display_resolution(self) -> tuple[int, int]:
        """Current screen resolution in pixels."""
        ...
