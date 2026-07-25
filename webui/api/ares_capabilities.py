"""Capability registry for ARES backend-specific UI affordances."""

from __future__ import annotations

from api.backend_selector import BACKEND_JROS, normalize_backend


CAPABILITIES: dict[str, dict[str, bool]] = {
    "cloud_provider_model_settings": {BACKEND_JROS: True},
    "mcp_server_config": {BACKEND_JROS: True},
    "messaging_gateway": {BACKEND_JROS: True},
    "kanban": {BACKEND_JROS: True},
    "delegate_task": {BACKEND_JROS: True},
    "character_persona_editing": {BACKEND_JROS: True},
    "voice_settings": {BACKEND_JROS: True},
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
    result = {capability: bool(matrix.get(selected, False)) for capability, matrix in CAPABILITIES.items()}
    return result
