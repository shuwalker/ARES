"""Capability registry for ARES backend-specific UI affordances."""
from __future__ import annotations

from api.backend_catalog import JAEGER_BACKEND_ID
from api.backend_selector import VALID_BACKENDS, normalize_backend


CAPABILITIES: dict[str, dict[str, bool]] = {
    "cloud_provider_model_settings": {
        "hermes_local": True,
        JAEGER_BACKEND_ID: False,
    },
    "mcp_server_config": {
        "hermes_local": True,
        JAEGER_BACKEND_ID: False,
    },
    "messaging_gateway": {
        "hermes_local": True,
        JAEGER_BACKEND_ID: False,
    },
    "kanban": {
        "hermes_local": True,
        JAEGER_BACKEND_ID: False,
    },
    "delegate_task": {
        "hermes_local": True,
        JAEGER_BACKEND_ID: False,
    },
    "character_persona_editing": {
        "hermes_local": False,
        JAEGER_BACKEND_ID: True,
    },
    "voice_settings": {
        "hermes_local": True,
        JAEGER_BACKEND_ID: False,
    },
}


def _jros_ares_tools_enabled() -> bool:
    try:
        from api.config import get_config

        return bool(get_config().get("jros_ares_tools_enabled"))
    except Exception:
        return False


def capabilities_for_backend(backend: str) -> dict[str, bool]:
    """Return UI capability flags for one normalized ARES backend."""
    selected = normalize_backend(backend)
    if selected not in VALID_BACKENDS:
        return {capability: False for capability in CAPABILITIES}
    result = {
        capability: bool(matrix.get(selected, False))
        for capability, matrix in CAPABILITIES.items()
    }
    if selected == JAEGER_BACKEND_ID and _jros_ares_tools_enabled():
        result["kanban"] = True
    return result
