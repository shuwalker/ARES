# ArmBridge — the connection between the ARES agent and the robot arm.
# LLM tool calls hit execute_goal(); everything else is handled internally.
#
# Arm goals (home, move, stop) are handled by BehaviorTreePlanner.
# Non-arm commands (connect, disconnect) are handled directly.

import logging
from .state import WorldModel
from .safety import SafetyMonitor
from .arm import ArmController
from ...planner.planner import BehaviorTreePlanner

logger = logging.getLogger("ares.robot.bridge")


class ArmBridge:
    def __init__(self, brain_path: str | None = None) -> None:
        # Build the full stack: world model → safety → arm controller → planner
        self.world = WorldModel()
        self.safety = SafetyMonitor(self.world)
        self.arm = ArmController(self.world, self.safety)
        self.planner = BehaviorTreePlanner(self.world, self.arm, brain_path)

    def execute_goal(self, goal: str) -> str:
        """
        Main entry point for LLM tool calls.
        Takes a plain-language goal, plans it via behavior tree, runs it.
        Returns a human-readable result string.
        """
        logger.info(f"ArmBridge: executing goal '{goal}'")

        g = goal.strip().lower()

        # Non-arm commands handled directly (no BT needed)
        if "connect" in g and "disconnect" not in g:
            ok = self.arm.connect()
            return "Arm connected" if ok else "Connection failed"

        if "disconnect" in g:
            self.arm.disconnect()
            return "Arm disconnected"

        # Arm motion goals → behavior tree
        tree = self.planner.plan_arm_goal(goal)
        if tree is None:
            return f"Could not understand goal: '{goal}'. Try: home, stop, connect, disconnect, or 'move to x=N y=N z=N'."

        ok = self.planner.execute(tree)

        if "stop" in g or "halt" in g:
            return "Emergency stop triggered"
        if "home" in g:
            return "Arm homed successfully" if ok else "Home failed — check connection"
        return f"Move completed" if ok else f"Move failed — safety check or connection issue"

    def get_status(self) -> str:
        """Return a plain-text status string for the arm."""
        state = self.arm.get_state()
        pos = state["position"]
        return (
            f"connected={state['connected']} | "
            f"position x={pos.get('x')} y={pos.get('y')} z={pos.get('z')} | "
            f"safety_stop={state['safety_stop']} | "
            f"last_command='{state['last_command']}'"
        )
