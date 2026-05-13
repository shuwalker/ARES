# Safety monitor — pure hard rules, no LLM involved.
# If any check returns False, the arm does not move. Period.

import logging
from .state import WorldModel

logger = logging.getLogger("ares.robot.safety")

# Safe workspace bounds for a typical desktop robot arm (millimeters from home)
WORKSPACE_LIMITS = {
    "x": (-500, 500),
    "y": (-500, 500),
    "z": (0, 500),   # z=0 is the table surface — never go below it
}


class SafetyMonitor:
    def __init__(self, world: WorldModel) -> None:
        self.world = world

    def emergency_stop(self) -> None:
        """Immediately halt all movement. Sets safety_stop flag on the world model."""
        self.world.safety_stop = True
        self.world.touch()
        logger.critical("EMERGENCY STOP triggered — arm movement blocked")

    def check_limits(self, position: dict) -> bool:
        """Return True if the position is inside the safe workspace, False if out of bounds."""
        for axis, (low, high) in WORKSPACE_LIMITS.items():
            value = position.get(axis, 0)
            if not (low <= value <= high):
                logger.warning(
                    f"Position out of bounds: {axis}={value} (allowed {low}..{high})"
                )
                return False
        return True

    def is_safe_to_move(self, position: dict) -> bool:
        """Full safety gate — checks e-stop flag AND workspace limits."""
        if self.world.safety_stop:
            logger.warning("Move blocked: safety stop is active")
            return False
        return self.check_limits(position)

    def reset_safety_stop(self) -> None:
        """Clear the emergency stop. Must be called explicitly before the arm can move again."""
        self.world.safety_stop = False
        self.world.touch()
        logger.info("Safety stop cleared — arm movement re-enabled")
