"""Capability registry for ARES backend-specific UI affordances."""

from __future__ import annotations

from api.backend_selector import (
    BACKEND_HERMES,
    BACKEND_HYBRID,
    BACKEND_JROS,
    VALID_BACKENDS,
    normalize_backend,
    should_register_jros_tools,
)


CAPABILITIES: dict[str, dict[str, bool]] = {
    "cloud_provider_model_settings": {
        BACKEND_HERMES: True,
        BACKEND_JROS: False,
        BACKEND_HYBRID: True,
    },
    "mcp_server_config": {
        BACKEND_HERMES: True,
        BACKEND_JROS: False,
        BACKEND_HYBRID: True,
    },
    "messaging_gateway": {
        BACKEND_HERMES: True,
        BACKEND_JROS: False,
        BACKEND_HYBRID: True,
    },
    "kanban": {
        BACKEND_HERMES: True,
        BACKEND_JROS: False,
        BACKEND_HYBRID: True,
    },
    "delegate_task": {
        BACKEND_HERMES: True,
        BACKEND_JROS: False,
        BACKEND_HYBRID: True,
    },
    "character_persona_editing": {
        BACKEND_HERMES: False,
        BACKEND_JROS: True,
        BACKEND_HYBRID: True,
    },
    "voice_settings": {
        BACKEND_HERMES: True,
        BACKEND_JROS: False,
        BACKEND_HYBRID: True,
    },
}


def _jros_hermes_tools_enabled() -> bool:
    try:
        from api.config import get_config

        return bool(get_config().get("jros_hermes_tools_enabled"))
    except Exception:
        return False


def capabilities_for_backend(backend: str) -> dict[str, bool]:
    """Return UI capability flags for one normalized ARES backend."""
    selected = normalize_backend(backend)
    if selected not in VALID_BACKENDS:
        selected = BACKEND_JROS
    result = {capability: bool(matrix.get(selected, False)) for capability, matrix in CAPABILITIES.items()}

    if selected == BACKEND_HYBRID:
        result["character_persona_editing"] = should_register_jros_tools({"ares_backend": BACKEND_HYBRID})
    if selected == BACKEND_JROS and _jros_hermes_tools_enabled():
        result["kanban"] = True
    return result
