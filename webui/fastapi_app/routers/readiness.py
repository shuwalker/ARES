"""Readiness rollup and capability checks."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from ..adapters import AdapterRegistry
from ..dependencies import get_adapter_registry
from ..request_context import RequestIdentity, profile_scope, require_identity

router = APIRouter(tags=["readiness"])

@router.get("/api/readiness")
def readiness(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    registry: Annotated[AdapterRegistry, Depends(get_adapter_registry)],
):
    """
    Roll up readiness across Profile, Connections, and Execution Capabilities.
    """
    from api import profiles as profiles_api
    from api.config import load_settings
    
    # 1. Profile Ready: A local profile exists and is active
    with profile_scope(identity.profile):
        try:
            active_profile = profiles_api.get_active_profile_name()
            # The implicit "default" profile name exists before a person has
            # saved any Local Profile. Readiness must reflect completed profile
            # setup, not merely the fallback name returned by profile routing.
            profile_ready = bool(load_settings().get("onboarding_completed"))
        except Exception:
            active_profile = None
            profile_ready = False

    # 2. Connection Ready: the explicitly elected runtime reports connected.
    records = registry.connection_records(profile=active_profile)
    connections = records.get("connections", [])
    selected_id = str(records.get("selected") or "")
    selected_runtime = next(
        (
            connection
            for connection in connections
            if connection.get("kind") == "runtime"
            and connection.get("id") == selected_id
        ),
        None,
    )
    connection_ready = bool(
        selected_runtime
        and selected_runtime.get("health", {}).get("state") == "connected"
        and selected_runtime.get("health", {}).get("available") is True
    )

    # 3. Execution Available: only the elected runtime supplies execution.
    capabilities = set(selected_runtime.get("capabilities", [])) if connection_ready else set()
    execution_available = bool(capabilities)

    return {
        "profile_ready": profile_ready,
        "connection_ready": connection_ready,
        "execution_available": execution_available,
        "capabilities": sorted(capabilities),
        "profile": active_profile,
        "selected_connection": selected_id or None,
        "connections": connections,
    }

__all__ = ["router"]
