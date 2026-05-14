"""ARES Cognitive Loop — the autonomous reasoning engine.

The cognitive loop is ARES's brain cycle. It's what makes ARES autonomous
rather than purely reactive. Based on patterns from Claude Code (iterative
agent loop), SAM (2×2 guidance matrix), and Lilith (ZMQ-synchronized state).

Architecture:

    ┌─────────────────────────────────┐
    │         CognitiveLoop            │
    │                                  │
    │  1. PERCEIVE — observe inputs    │
    │  2. THINK   — reason & plan      │
    │  3. ACT     — execute actions    │
    │  4. REFLECT — evaluate results   │
    │                                  │
    │  ┌──────────────────────────┐   │
    │  │   Guidance Matrix         │   │
    │  │                          │   │
    │  │   Low Urgency  │ High    │   │
    │  │   ───────────────────────│   │
    │  │   Observe      │ React   │   │
    │  │   Plan         │ Execute │   │
    │  │   Research     │ Decide  │   │
    │  └──────────────────────────┘   │
    │                                  │
    │  Stop Hooks:                     │
    │  - Budget exhausted              │
    │  - User interrupt                │
    │  - Safety boundary               │
    │  - Goal completed                │
    └─────────────────────────────────┘

The loop connects to Hermes as the LLM backend, uses the ZMQ bus for
face/voice/robot state updates, and the personality system for behavior
shaping.
"""

from __future__ import annotations

import enum
import logging
import time
from dataclasses import dataclass, field
from typing import Callable, List, Optional

from ares.core.bus import ARESBus, BusMessage, get_bus
from ares.core.personality import CharacterProfile, DEFAULT_PROFILE, load_personality
from ares.core.face_state import FaceState, get_face_config

logger = logging.getLogger("ares.cognitive")


# ---------------------------------------------------------------------------
# Loop phases
# ---------------------------------------------------------------------------


class Phase(enum.Enum):
    """The four phases of each cognitive cycle."""

    PERCEIVE = "perceive"  # Observe inputs (messages, events, sensor data)
    THINK = "think"  # Reason about what to do
    ACT = "act"  # Execute actions
    REFLECT = "reflect"  # Evaluate results, update state


class Urgency(enum.Enum):
    """Urgency level from the guidance matrix."""

    LOW = "low"  # No immediate action needed
    MEDIUM = "medium"  # Something needs attention soon
    HIGH = "high"  # Needs immediate response
    CRITICAL = "critical"  # Safety or system-critical


# ---------------------------------------------------------------------------
# Guidance Matrix — determines loop behavior based on urgency
# ---------------------------------------------------------------------------


@dataclass
class GuidanceMatrix:
    """2×2 guidance matrix from SAM. Maps urgency × context to behavior.

    Low urgency  → Observe/Plan/Research (deliberate)
    High urgency → React/Execute/Decide (fast)

    The personality's directness and aggression sliders modulate how
    aggressively the loop shifts from observe to act.
    """

    # Thresholds for urgency classification
    low_threshold: float = 0.3  # Below this → LOW urgency
    high_threshold: float = 0.7  # Above this → HIGH urgency

    def classify(self, urgency_score: float) -> Urgency:
        """Classify a score into an urgency level."""
        if urgency_score >= self.high_threshold:
            return Urgency.HIGH
        elif urgency_score >= self.low_threshold:
            return Urgency.MEDIUM
        return Urgency.LOW

    def guidance_for(self, urgency: Urgency, personality: CharacterProfile = None) -> dict:
        """Return guidance dict for the given urgency level.

        The personality modulates timing thresholds and behavior.
        """
        if personality is None:
            personality = DEFAULT_PROFILE

        directness = personality.expression.directness
        aggression = personality.expression.aggression
        openness = personality.hexaco.openness

        base = {
            Urgency.LOW: {
                "mode": "observe",
                "max_iterations": 3,
                "think_time_ms": 2000,
                "plan": True,
                "research": True,
                "description": "No immediate need. Observe, research, plan.",
            },
            Urgency.MEDIUM: {
                "mode": "plan",
                "max_iterations": 5,
                "think_time_ms": 1000,
                "plan": True,
                "research": True,
                "description": "Something needs attention. Plan and prepare.",
            },
            Urgency.HIGH: {
                "mode": "execute",
                "max_iterations": 10,
                "think_time_ms": 500,
                "plan": False,
                "research": False,
                "description": "Immediate action needed. Execute decisively.",
            },
        }

        guidance = base.get(urgency, base[Urgency.LOW]).copy()

        # Personality modulation
        if directness > 0.8:
            guidance["think_time_ms"] = int(guidance["think_time_ms"] * 0.7)
        if aggression > 0.7:
            guidance["max_iterations"] = min(guidance["max_iterations"] + 2, 15)
        if openness > 0.7:
            guidance["research"] = True  # Always research if high openness

        return guidance


# ---------------------------------------------------------------------------
# Stop conditions
# ---------------------------------------------------------------------------


class StopReason(enum.Enum):
    """Why the cognitive loop stopped."""

    BUDGET_EXHAUSTED = "budget_exhausted"  # Iteration or token budget hit limit
    USER_INTERRUPT = "user_interrupt"  # User sent a stop signal
    GOAL_COMPLETED = "goal_completed"  # Task finished successfully
    SAFETY_BOUNDARY = "safety_boundary"  # Hit a safety constraint
    ERROR = "error"  # Unrecoverable error
    SHUTDOWN = "shutdown"  # System shutting down


@dataclass
class StopHook:
    """A condition that can halt the cognitive loop.

    Hooks are checked after each cycle. If any hook returns a StopReason
    (not None), the loop halts with that reason.
    """

    name: str
    check: Callable[[], Optional[StopReason]]
    priority: int = 0  # Lower = checked first


# ---------------------------------------------------------------------------
# Cognitive State — tracks loop progress
# ---------------------------------------------------------------------------


@dataclass
class ThoughtNodeRecord:
    """A single reasoning step recorded for the cycle's DAG.

    Kept dependency-free (plain dict / dataclass) so core/ doesn't import
    Pydantic. The API layer maps these to `models.cognitive.ThoughtNode`.
    """

    id: str
    parent_ids: List[str]
    label: str
    status: str  # "pending" | "running" | "done" | "failed"
    duration_ms: int = 0
    evidence: List[dict] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "parent_ids": list(self.parent_ids),
            "label": self.label,
            "status": self.status,
            "duration_ms": self.duration_ms,
            "evidence": list(self.evidence),
        }


@dataclass
class CognitiveState:
    """Mutable state tracked across loop iterations."""

    cycle: int = 0  # Current cycle number
    phase: Phase = Phase.PERCEIVE  # Current phase
    urgency: Urgency = Urgency.LOW  # Current urgency level
    budget_remaining: float = 1.0  # 0.0 to 1.0, fraction of budget left
    tokens_used: int = 0  # Total tokens consumed
    last_input: Optional[dict] = None  # Most recent perceived input
    last_action: Optional[dict] = None  # Most recent action taken
    last_reflection: Optional[str] = None  # Most recent reflection
    face_state: FaceState = FaceState.IDLE  # Current face state
    started_at: float = field(default_factory=time.time)
    errors: List[str] = field(default_factory=list)
    # Reasoning DAG for the current cycle. Reset at the top of each cycle.
    # API layer reads this into `CognitiveSnapshot.thought.branches`.
    branches: List[ThoughtNodeRecord] = field(default_factory=list)

    def to_dict(self) -> dict:
        return {
            "cycle": self.cycle,
            "phase": self.phase.value,
            "urgency": self.urgency.value,
            "budget_remaining": self.budget_remaining,
            "tokens_used": self.tokens_used,
            "face_state": self.face_state.value,
            "started_at": self.started_at,
            "errors": self.errors,
            "branches": [b.to_dict() for b in self.branches],
        }


# ---------------------------------------------------------------------------
# Cognitive Loop — the main loop
# ---------------------------------------------------------------------------


class CognitiveLoop:
    """ARES's autonomous reasoning loop.

    Connects:
    - Personality system (shapes behavior per guidance matrix)
    - ZMQ bus (publishes face state, subscribes to inputs)
    - Hermes (LLM backend for thinking and acting)
    - Memory (stores and retrieves facts)

    Usage:
        loop = CognitiveLoop(personality=load_personality())
        loop.add_stop_hook(StopHook("budget", lambda: ...))
        result = loop.run(goal="Build the MCP server")
    """

    def __init__(
        self,
        personality: CharacterProfile = None,
        bus: ARESBus = None,
        max_cycles: int = 50,
        budget_tokens: int = 100000,
    ):
        self.personality = personality or DEFAULT_PROFILE
        self.bus = bus or get_bus()
        self.max_cycles = max_cycles
        self.budget_tokens = budget_tokens

        self.guidance = GuidanceMatrix()
        self.state = CognitiveState()
        self.stop_hooks: List[StopHook] = []
        self._running = False

        # Phase handlers — override for custom behavior
        self._perceive_handlers: List[Callable] = []
        self._think_handlers: List[Callable] = []
        self._act_handlers: List[Callable] = []
        self._reflect_handlers: List[Callable] = []

        # Phase-change observer — called as on_phase_change(state) after every
        # phase transition. Used by the API server to broadcast cognitive
        # snapshots over the WebSocket. Set to a no-op by default so the loop
        # works headless.
        self.on_phase_change: Callable[["CognitiveState"], None] = lambda _state: None

        # Register default stop hooks
        self.add_stop_hook(
            StopHook(
                "budget_exhausted",
                lambda: StopReason.BUDGET_EXHAUSTED if self.state.budget_remaining <= 0 else None,
                priority=0,
            )
        )
        self.add_stop_hook(
            StopHook(
                "max_cycles",
                lambda: StopReason.BUDGET_EXHAUSTED if self.state.cycle >= self.max_cycles else None,
                priority=0,
            )
        )

    def add_stop_hook(self, hook: StopHook) -> None:
        """Add a stop condition to the loop."""
        self.stop_hooks.append(hook)
        self.stop_hooks.sort(key=lambda h: h.priority)

    def on_perceive(self, handler: Callable) -> None:
        """Register a perceive phase handler."""
        self._perceive_handlers.append(handler)

    def on_think(self, handler: Callable) -> None:
        """Register a think phase handler."""
        self._think_handlers.append(handler)

    def on_act(self, handler: Callable) -> None:
        """Register an act phase handler."""
        self._act_handlers.append(handler)

    def on_reflect(self, handler: Callable) -> None:
        """Register a reflect phase handler."""
        self._reflect_handlers.append(handler)

    # -- Phase implementations (default — override with handlers) ---------

    def _perceive(self, goal: str) -> dict:
        """PERCEIVE: Gather inputs from bus, memory, and external sources."""
        input_data = {"goal": goal, "cycle": self.state.cycle}

        # Check bus for new messages
        brain_sub = None
        try:
            brain_sub = self.bus.subscribe("brain_output")
            msg = brain_sub.receive_message(timeout_ms=500)
            if msg:
                input_data["bus_message"] = msg.to_dict()
        except Exception:
            pass
        finally:
            if brain_sub:
                brain_sub.close()

        # Call registered handlers
        for handler in self._perceive_handlers:
            try:
                result = handler(self.state, goal)
                if result:
                    input_data.update(result)
            except Exception as e:
                logger.warning("Perceive handler error: %s", e)
                self.state.errors.append(str(e))

        self.state.phase = Phase.PERCEIVE
        self.state.last_input = input_data
        self._notify_phase_change()
        return input_data

    def _think(self, input_data: dict) -> dict:
        """THINK: Reason about inputs and plan actions.

        Uses the guidance matrix to determine how much thinking to do
        based on urgency and personality.
        """
        # Assess urgency
        urgency_score = input_data.get("urgency", 0.3)
        self.state.urgency = self.guidance.classify(urgency_score)
        guidance = self.guidance.guidance_for(self.state.urgency, self.personality)

        plan = {
            "phase": "think",
            "urgency": self.state.urgency.value,
            "guidance": guidance,
            "actions": [],
        }

        # Call registered handlers
        for handler in self._think_handlers:
            try:
                result = handler(self.state, input_data, guidance)
                if result:
                    plan.update(result)
            except Exception as e:
                logger.warning("Think handler error: %s", e)
                self.state.errors.append(str(e))

        self.state.phase = Phase.THINK
        self._notify_phase_change()
        return plan

    def _act(self, plan: dict) -> dict:
        """ACT: Execute planned actions."""
        actions_taken = {
            "phase": "act",
            "actions": [],
        }

        # Update face state to thinking/acting
        self._update_face(FaceState.THINKING)

        # Call registered handlers
        for handler in self._act_handlers:
            try:
                result = handler(self.state, plan)
                if result:
                    actions_taken["actions"].append(result)
            except Exception as e:
                logger.warning("Act handler error: %s", e)
                self.state.errors.append(str(e))

        self.state.phase = Phase.ACT
        self.state.last_action = actions_taken
        self._notify_phase_change()
        return actions_taken

    def _reflect(self, actions_taken: dict) -> str:
        """REFLECT: Evaluate what happened and update state."""
        reflection = f"Cycle {self.state.cycle}: "

        if self.state.errors:
            reflection += f"{len(self.state.errors)} errors. "
        else:
            reflection += "No errors. "

        n_actions = len(actions_taken.get("actions", []))
        reflection += f"{n_actions} actions taken. "
        reflection += f"Urgency: {self.state.urgency.value}. "
        reflection += f"Budget remaining: {self.state.budget_remaining:.0%}."

        # Call registered handlers
        for handler in self._reflect_handlers:
            try:
                result = handler(self.state, actions_taken)
                if result:
                    reflection += f" {result}"
            except Exception as e:
                logger.warning("Reflect handler error: %s", e)

        self.state.phase = Phase.REFLECT
        self.state.last_reflection = reflection
        self._notify_phase_change()

        # Update face based on result
        if self.state.errors:
            self._update_face(FaceState.THINKING)  # Stay engaged
        else:
            self._update_face(FaceState.IDLE)  # Relaxed

        return reflection

    def _notify_phase_change(self) -> None:
        """Append a DAG node for this phase, then fire the observer.

        Observer exceptions are swallowed — the loop must not crash because a
        UI subscriber misbehaved.
        """
        self._record_phase_node()
        try:
            self.on_phase_change(self.state)
        except Exception as e:
            logger.warning("on_phase_change observer error: %s", e)

    def _record_phase_node(self) -> None:
        """Append a ThoughtNodeRecord for the current phase to the cycle DAG.

        Chains as a child of the previous node so the default DAG is a
        linear perceive→think→act→reflect path. Handlers that emit
        additional nodes (via `emit_thought_node`) attach as siblings.
        """
        import uuid

        prev_id = self.state.branches[-1].id if self.state.branches else None
        node = ThoughtNodeRecord(
            id=uuid.uuid4().hex[:8],
            parent_ids=[prev_id] if prev_id else [],
            label=self.state.phase.value,
            status="done",
        )
        self.state.branches.append(node)

    def emit_thought_node(
        self,
        label: str,
        status: str = "done",
        parent_ids: Optional[List[str]] = None,
        evidence: Optional[List[dict]] = None,
        duration_ms: int = 0,
    ) -> str:
        """Public hook for phase handlers to record extra reasoning steps.

        Returns the generated node id so callers can chain children.
        """
        import uuid

        node = ThoughtNodeRecord(
            id=uuid.uuid4().hex[:8],
            parent_ids=(
                list(parent_ids) if parent_ids else ([self.state.branches[-1].id] if self.state.branches else [])
            ),
            label=label,
            status=status,
            duration_ms=duration_ms,
            evidence=list(evidence or []),
        )
        self.state.branches.append(node)
        return node.id

    def _update_face(self, state: FaceState) -> None:
        """Publish face state update to the bus."""
        config = get_face_config(state)
        msg = BusMessage(
            type="face_state",
            source="cognitive_loop",
            payload={
                "state": state.value,
                "color": list(config.color),
                "opacity": config.opacity,
                "pulse_speed": config.pulse_speed,
                "pulse_amount": config.pulse_amount,
            },
        )
        self.bus.dispatch(msg)

    # -- Check stop hooks --------------------------------------------------

    def _check_stop_hooks(self) -> Optional[StopReason]:
        """Check all stop hooks. Return first non-None reason, or None to continue."""
        for hook in self.stop_hooks:
            try:
                reason = hook.check()
                if reason is not None:
                    logger.info("Stop hook %s triggered: %s", hook.name, reason.value)
                    return reason
            except Exception as e:
                logger.warning("Stop hook %s error: %s", hook.name, e)
        return None

    # -- Main loop ---------------------------------------------------------

    def run(self, goal: str) -> dict:
        """Run the cognitive loop until completion or stop condition.

        Args:
            goal: The objective to pursue.

        Returns:
            dict with cycle count, stop reason, final state, and reflections.
        """
        self._running = True
        self.state = CognitiveState()
        self._update_face(FaceState.AWAKENED)

        reflections = []

        logger.info("Cognitive loop starting. Goal: %s", goal)

        while self._running:
            self.state.cycle += 1
            # Reset the reasoning DAG for this cycle. Prior cycle's branches
            # have already been observed by the UI and (will be) persisted
            # by the API layer via the snapshot stream.
            self.state.branches = []

            # Check stop hooks
            stop_reason = self._check_stop_hooks()
            if stop_reason is not None:
                logger.info("Loop stopped: %s", stop_reason.value)
                break

            # PERCEIVE
            input_data = self._perceive(goal)

            # Check for interrupt
            if input_data.get("interrupt"):
                self._running = False
                stop_reason = StopReason.USER_INTERRUPT
                break

            # THINK
            plan = self._think(input_data)

            # Check for goal completion
            if plan.get("goal_completed"):
                stop_reason = StopReason.GOAL_COMPLETED
                break

            # ACT
            actions_taken = self._act(plan)

            # REFLECT
            reflection = self._reflect(actions_taken)
            reflections.append(reflection)

            # Update budget
            self.state.budget_remaining -= 0.02  # ~2% per cycle

        # Final state
        self._update_face(FaceState.SLEEPING)

        result = {
            "goal": goal,
            "cycles": self.state.cycle,
            "stop_reason": (stop_reason or StopReason.BUDGET_EXHAUSTED).value,
            "state": self.state.to_dict(),
            "reflections": reflections,
        }

        logger.info("Cognitive loop complete. Cycles: %d, Reason: %s", self.state.cycle, result["stop_reason"])

        return result

    def stop(self) -> None:
        """Signal the loop to stop after the current cycle."""
        self._running = False


# ---------------------------------------------------------------------------
# Convenience
# ---------------------------------------------------------------------------


def create_loop(
    personality: CharacterProfile = None,
    max_cycles: int = 50,
) -> CognitiveLoop:
    """Create a cognitive loop with defaults."""
    if personality is None:
        personality = load_personality()
    return CognitiveLoop(personality=personality, max_cycles=max_cycles)
