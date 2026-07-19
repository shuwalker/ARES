"""ARES self-persistence contract and prompt wrapper.

This is the ARES-owned continuity layer above swappable external backends.
ARES owns shared resources and orchestration; inference and identity remain
projections of the explicitly elected runtime.

The module is intentionally pure: no filesystem writes, no Ares/JROS imports,
and no backend internals. It returns JSON-safe data for UI/API surfaces and a
small prompt section for the active agent run.
"""

from __future__ import annotations

from typing import Any


SELF_PERSISTENCE_CAPABILITIES = (
    "identity_projection",
    "self_audit",
    "promise_to_task_capture",
    "autonomous_follow_through",
    "task_continuity",
    "cross_session_context",
    "embodied_presence",
)

_DEFERRED_FORK_RATIONALE = (
    "ARES talks through stable adapters so external runtimes can be replaced "
    "without rewriting shared memory, tools, sessions, or policy."
)


def _active_backend(config: dict[str, Any] | None) -> str:
    from api.backend_selector import get_active_backend

    return get_active_backend(config or {})


def should_inject_self_persistence(config: dict[str, Any] | None) -> bool:
    """Return whether ARES should add its self-persistence prompt section.

    Enabled by default because this is ARES product behavior, not a backend
    feature. A config value of ``ares_self_persistence_enabled: false`` disables
    it for diagnostics or strict upstream-Ares comparison runs.
    """

    if not isinstance(config, dict):
        return True
    return config.get("ares_self_persistence_enabled", True) is not False


def build_self_persistence_contract(config: dict[str, Any] | None) -> dict[str, Any]:
    """Return the stable ARES contract for continuity and presentation."""

    return {
        "identity_owner": "active_runtime",
        "identity_policy": "projection-only",
        "backend_policy": "adapter-first",
        "fork_decision": "deferred",
        "prevents_redo_work": True,
        "active_backend": _active_backend(config),
        "runtime_required": True,
        "capabilities": list(SELF_PERSISTENCE_CAPABILITIES),
        "backend_roles": {
            "ares": "shared_resources_routing_permissions_and_continuity",
            "active_runtime": "inference_and_projected_identity",
        },
        "rationale": _DEFERRED_FORK_RATIONALE,
    }


def render_self_persistence_prompt(config: dict[str, Any] | None) -> str:
    """Render a compact prompt section enforcing ARES ownership boundaries."""

    contract = build_self_persistence_contract(config)
    capabilities = ", ".join(contract["capabilities"])
    return (
        "ARES owns shared resources, routing, permissions, and task continuity. "
        "The explicitly selected external runtime supplies inference and projected identity. "
        "ARES identity APIs are projections of the active runtime, not a canonical soul. "
        "Do not bury task continuity inside a swappable backend.\n\n"
        f"Active runtime: {contract['active_backend'] or 'none selected'}\n"
        "Adapter policy: adapter-first; fork decision deferred.\n"
        f"ARES presentation/continuity capabilities: {capabilities}.\n"
        "Operational rule: promises, follow-up obligations, self-audit results, "
        "and continuity state must be treated as ARES product behavior that can "
        "survive backend replacement. Persona and runtime state remain owned by "
        "the active backend."
    )
