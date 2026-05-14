"""Desktop embodiment — Mac Studio implementation.

Uses AVFoundation for camera, CoreAudio for mic/speakers,
AppKit for screen resolution. All through Python wrappers.
"""

from __future__ import annotations

from ..interface import Embodiment


class DesktopEmbodiment(Embodiment):
    """Mac Studio embodiment — camera, mic, speakers, screen."""

    def send_text(self, text: str) -> None:
        """Print to stdout for now. Future: macOS notification center."""
        print(text)

    def capture_image(self) -> bytes | None:
        """Capture from webcam. Not yet implemented."""
        return None

    def capture_audio(self, duration_seconds: float) -> bytes | None:
        """Capture from mic. Not yet implemented."""
        return None

    def play_audio(self, audio: bytes) -> None:
        """Play through speakers. Not yet implemented."""
        pass

    def get_display_resolution(self) -> tuple[int, int]:
        """Return Mac Studio display resolution."""
        try:
            import subprocess

            result = subprocess.run(
                ["system_profiler", "SPDisplaysDataType"], capture_output=True, text=True, timeout=5
            )
            for line in result.stdout.split("\n"):
                if "Resolution:" in line:
                    parts = line.split(":")[1].strip().split(" x ")
                    return int(parts[0]), int(parts[1])
        except Exception:
            pass
        return 1920, 1080  # reasonable default
