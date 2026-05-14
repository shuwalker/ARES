# TaskPlanner — converts plain language goals into a list of arm commands.
# No LLM. Regex only. Simple, predictable, safe.
#
# Supported goals:
#   "home"                       → home the arm
#   "move to x=100 y=50 z=200"  → move to position
#   "stop"                       → emergency stop
#   "connect"                    → connect to arm
#   "disconnect"                 → disconnect from arm

import logging
import re

logger = logging.getLogger("ares.robot.planner")


class TaskPlanner:
    def plan(self, goal: str) -> list[dict]:
        """
        Parse a plain-language goal and return a list of arm commands.
        Each command is a dict like {"action": "move_to", "position": {...}}.
        Returns an empty list if the goal isn't understood.
        """
        goal = goal.strip().lower()

        # "home the arm" / "go home" / "home"
        if re.search(r"\bhome\b", goal):
            return [{"action": "home"}]

        # "stop" / "emergency stop" / "halt"
        if re.search(r"\b(stop|halt|emergency\s*stop)\b", goal):
            return [{"action": "stop"}]

        # "connect" / "connect arm"
        if re.search(r"\bconnect\b", goal) and "disconnect" not in goal:
            return [{"action": "connect"}]

        # "disconnect" / "disconnect arm"
        if re.search(r"\bdisconnect\b", goal):
            return [{"action": "disconnect"}]

        # "move to x=100 y=50 z=200" — all three axes required
        move_match = re.search(
            r"x\s*=\s*(-?\d+(?:\.\d+)?)"
            r".*?y\s*=\s*(-?\d+(?:\.\d+)?)"
            r".*?z\s*=\s*(-?\d+(?:\.\d+)?)",
            goal,
        )
        if move_match:
            x, y, z = (float(v) for v in move_match.groups())
            return [{"action": "move_to", "position": {"x": x, "y": y, "z": z}}]

        # Nothing matched
        logger.warning(f"Planner could not understand goal: '{goal}'")
        return []
