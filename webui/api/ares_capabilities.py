"""Capability registry for ARES backend-specific UI affordances."""
from __future__ import annotations

from api.backend_selector import VALID_BACKENDS, normalize_backend


CAPABILITIES: dict[str, dict[str, bool]] = {
    "cloud_provider_model_settings": {
        "hermes_local": True,
        "jros_local": False,
    },
    "mcp_server_config": {
        "hermes_local": True,
        "jros_local": False,
    },
    "messaging_gateway": {
        "hermes_local": True,
        "jros_local": False,
    },
    "kanban": {
        "hermes_local": True,
        "jros_local": False,
    },
    "delegate_task": {
        "hermes_local": True,
        "jros_local": False,
    },
    "character_persona_editing": {
        "hermes_local": False,
        "jros_local": True,
    },
    "voice_settings": {
        "hermes_local": True,
        "jros_local": False,
    },
}


def capabilities_for_backend(backend: str) -> dict[str, bool]:
    """Return UI capability flags for one normalized ARES backend."""
    selected = normalize_backend(backend)
    if selected not in VALID_BACKENDS:
        selected = "hermes_local"
    return {capability: bool(matrix.get(selected, False)) for capability, matrix in CAPABILITIES.items()}
