"""ARES 2 agent-stack manifest.

This module is intentionally small and concrete: it names the product shape
ARES is being rebuilt toward so the daemon, API, face app, and tests can share
one definition instead of scattering aspiration through comments.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any


@dataclass(frozen=True)
class StackLayer:
    """One layer in the embodied agent stack."""

    name: str
    responsibility: str
    first_milestone: str
    owns: tuple[str, ...] = field(default_factory=tuple)

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


@dataclass(frozen=True)
class AgentStack:
    """The rebuild target for ARES as a persistent embodied agent."""

    name: str
    thesis: str
    first_product: str
    non_goals: tuple[str, ...]
    layers: tuple[StackLayer, ...]

    def layer_names(self) -> tuple[str, ...]:
        return tuple(layer.name for layer in self.layers)

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "thesis": self.thesis,
            "first_product": self.first_product,
            "non_goals": list(self.non_goals),
            "layers": [layer.to_dict() for layer in self.layers],
        }


def default_agent_stack() -> AgentStack:
    """Return the canonical ARES 2 stack definition.

    ARES should feel like Jarvis/R2-D2: persistent, embodied, sensor-aware, and
    useful. Hermes Agent is one reasoning backend inside this stack, not the
    product boundary.
    """

    return AgentStack(
        name="ARES 2",
        thesis="Persistent embodied agent OS for an always-on AI avatar and tool-using operator.",
        first_product="AI avatar companion with memory, voice/text chat, visible tool activity, and content workflow tools.",
        non_goals=(
            "Chatbot-only UX",
            "Hermes-specific UI shell",
            "Unbounded autonomous AGI claims",
            "Hidden pipelines that humans cannot inspect or edit",
        ),
        layers=(
            StackLayer(
                name="presence",
                responsibility="Avatar, voice, state, emotion, idle behavior, and the feeling that ARES is present.",
                first_milestone="Swift face shows live state, chat, wake/listen/speak modes, and tool activity.",
                owns=("avatar", "voice_state", "emotion", "cognitive_activity_ui"),
            ),
            StackLayer(
                name="runtime",
                responsibility="24/7 process supervision, home directory, config, health, restart, and service lifecycle.",
                first_milestone="One always-on desktop process with safe startup/shutdown and no hardcoded user paths.",
                owns=("daemon", "api", "service_manager", "bootstrap", "health"),
            ),
            StackLayer(
                name="memory",
                responsibility="Identity, user preferences, episodic history, project memory, and summaries.",
                first_milestone="Every chat/tool run records durable memory and can retrieve relevant context.",
                owns=("identity", "preferences", "episodes", "projects", "summaries"),
            ),
            StackLayer(
                name="perception",
                responsibility="Continuous but permissioned sensors: mic, screen, camera, files, and later robot inputs.",
                first_milestone="Mic and screen/camera snapshots publish normalized observations to the bus.",
                owns=("microphone", "screen", "camera", "file_context", "robot_sensors"),
            ),
            StackLayer(
                name="reasoning",
                responsibility="Model routing, planning, reflection, and agent loops. Hermes is one backend here.",
                first_milestone="Chat and tool turns route through a swappable reasoning adapter with local/cloud fallback.",
                owns=("hermes_adapter", "local_llm", "cloud_llm", "planner", "reflection"),
            ),
            StackLayer(
                name="tools",
                responsibility="Real capabilities: web, code, files, browser/computer control, MCP, n8n, and creative apps.",
                first_milestone="Tool registry reports what ARES can do and executes safe, inspectable actions.",
                owns=("mcp", "browser", "filesystem", "code", "n8n", "media_tools"),
            ),
            StackLayer(
                name="approval",
                responsibility="Policy for what ARES can do alone, what needs confirmation, and what is blocked.",
                first_milestone="One approval service handles installs, file deletion, publishing, spending, and device control.",
                owns=("policy", "checkpoints", "audit", "user_interrupts"),
            ),
            StackLayer(
                name="workflows",
                responsibility="Composable jobs such as content creation, research, coding, automation, and robot tasks.",
                first_milestone="Content workflow creates brief, research, script, asset plan, and publish checklist.",
                owns=("content_creation", "research", "coding", "automation", "robot_jobs"),
            ),
        ),
    )


def stack_status() -> dict[str, Any]:
    """Serializable stack status for API/UI consumers."""

    stack = default_agent_stack()
    data = stack.to_dict()
    data["layer_count"] = len(stack.layers)
    data["ready"] = False
    data["current_milestone"] = "avatar_companion_foundation"
    return data
