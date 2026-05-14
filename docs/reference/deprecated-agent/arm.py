# ArmController — stub for the robot arm hardware driver.
# All methods log what they would do and return success.
# Swap in the real USB/serial driver here when hardware is ready.

import logging
from .state import WorldModel
from .safety import SafetyMonitor

logger = logging.getLogger("ares.robot.arm")


class ArmController:
    def __init__(self, world: WorldModel, safety: SafetyMonitor) -> None:
        self.world = world
        self.safety = safety

    def connect(self) -> bool:
        """Open connection to the arm. Stub — logs intent, marks connected."""
        logger.info("[STUB] Connecting to robot arm...")
        self.world.arm_connected = True
        self.world.touch()
        logger.info("[STUB] Arm connected")
        return True

    def disconnect(self) -> None:
        """Close connection to the arm."""
        logger.info("[STUB] Disconnecting from robot arm...")
        self.world.arm_connected = False
        self.world.touch()
        logger.info("[STUB] Arm disconnected")

    def get_state(self) -> dict:
        """Return current position and connection status."""
        return {
            "connected": self.world.arm_connected,
            "position": dict(self.world.arm_position),
            "safety_stop": self.world.safety_stop,
            "last_command": self.world.last_command,
            "last_updated": self.world.last_updated,
        }

    def move_to(self, position: dict) -> bool:
        """Move arm to the given position (x, y, z in mm). Stub — logs and updates world model."""
        if not self.world.arm_connected:
            logger.error("Cannot move: arm is not connected")
            return False

        if not self.safety.is_safe_to_move(position):
            logger.error(f"Cannot move: safety check failed for position {position}")
            return False

        logger.info(f"[STUB] Moving arm to {position}")
        self.world.arm_position = dict(position)
        self.world.last_command = f"move_to {position}"
        self.world.touch()
        logger.info(f"[STUB] Arm moved to {position}")
        return True

    def home(self) -> bool:
        """Move arm to home position (0, 0, 0). Stub."""
        logger.info("[STUB] Homing arm...")
        return self.move_to({"x": 0, "y": 0, "z": 0})

    def stop(self) -> None:
        """Immediate halt — triggers emergency stop on the safety monitor."""
        logger.warning("[STUB] Stopping arm immediately")
        self.safety.emergency_stop()
        self.world.last_command = "stop"
        self.world.touch()
