"""ARES self-persistence contract and prompt wrapper.

This is the ARES-owned layer above swappable backends. Hermes can remain the
agent loop and JROS can provide robotics/embodiment primitives, but identity,
task continuity, follow-through, and self-audit belong to ARES.

The module is intentionally pure: no filesystem writes, no Hermes/JROS imports,
and no backend internals. It returns JSON-safe data for UI/API surfaces and a
small prompt section for the active agent run.
"""

from __future__ import annotations

from typing import Any


SELF_PERSISTENCE_CAPABILITIES = (
    "durable_identity",
    "self_audit",
    "promise_to_task_capture",
    "autonomous_follow_through",
    "task_continuity",
    "cross_session_context",
    "embodied_presence",
)

ADAPTERS = ("hermes", "jros")


_DEFERRED_FORK_RATIONALE = (
    "ARES talks through stable adapters so Hermes Agent and JROS can be forked, "
    "replaced, or absorbed later without rewriting the user-facing ARES layer."
)


def _active_backend(config: dict[str, Any] | None) -> str:
    raw = ""
    if isinstance(config, dict):
        raw = str(config.get("ares_backend", "") or "").strip().lower()
    return raw if raw in {"hermes", "jros", "hybrid"} else "hermes"


def should_inject_self_persistence(config: dict[str, Any] | None) -> bool:
    """Return whether ARES should add its self-persistence prompt section.

    Enabled by default because this is ARES product behavior, not a backend
    feature. A config value of ``ares_self_persistence_enabled: false`` disables
    it for diagnostics or strict upstream-Hermes comparison runs.
    """

    if not isinstance(config, dict):
        return True
    return config.get("ares_self_persistence_enabled", True) is not False


def build_self_persistence_contract(config: dict[str, Any] | None) -> dict[str, Any]:
    """Return the stable ARES contract for the self-persistent person layer."""

    return {
        "identity_owner": "ares",
        "backend_policy": "adapter-first",
        "fork_decision": "deferred",
        "prevents_redo_work": True,
        "active_backend": _active_backend(config),
        "adapters": list(ADAPTERS),
        "capabilities": list(SELF_PERSISTENCE_CAPABILITIES),
        "backend_roles": {
            "hermes": "agent_loop_tools_memory_cron",
            "jros": "robotics_embodiment_persona_primitives",
            "ares": "identity_persistence_task_continuity_user_experience",
        },
        "rationale": _DEFERRED_FORK_RATIONALE,
    }


def render_self_persistence_prompt(config: dict[str, Any] | None) -> str:
    """Render a compact prompt section enforcing ARES ownership boundaries."""

    contract = build_self_persistence_contract(config)
    capabilities = ", ".join(contract["capabilities"])
    return (
        "ARES owns the experience layer and task continuity. "
        "Hermes supplies the agent loop. "
        "JROS supplies robotics, embodiment, and canonical persona identity. "
        "Do not bury task continuity inside a swappable backend.\n\n"
        f"Active backend mode: {contract['active_backend']}\n"
        "Adapter policy: adapter-first; fork decision deferred.\n"
        f"ARES-owned capabilities: {capabilities}.\n"
        "Operational rule: promises, follow-up obligations, self-audit results, "
        "and continuity state must be treated as ARES product behavior that can "
        "survive backend replacement."
    )
