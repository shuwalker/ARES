"""Auto-discovery endpoints for installed AI frameworks."""

from __future__ import annotations

from typing import Annotated
from fastapi import APIRouter, Depends

from ..dependencies import get_core_service
from ..request_context import RequestIdentity, profile_scope, require_identity, require_mutation_identity
from ..schemas import AIFrameworkDiscoveryResponse, ExtensibleResponse
from ..services import AresCoreService


router = APIRouter(tags=["discovery"])


@router.get("/api/discover/frameworks", response_model=AIFrameworkDiscoveryResponse)
def discover_frameworks(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    from api.ai_framework_discovery import discover_summary
    from datetime import datetime, timezone

    summary = discover_summary()
    summary["scanned_at"] = datetime.now(timezone.utc).isoformat()
    summary["profile"] = identity.profile
    return summary


@router.post("/api/discover/frameworks/apply", response_model=ExtensibleResponse)
def apply_discovered_frameworks(
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    """Persist discovered adapters into Local Profile settings."""
    from api.ai_framework_discovery import discover_frameworks
    from api.config import load_settings, save_settings

    with profile_scope(identity.profile):
        discovered = discover_frameworks()
        current = load_settings()
        connections = {}
        for adapter in discovered:
            if not adapter.detected:
                continue
            entry = {
                "enabled": True,
                "detected": True,
                "binary_path": adapter.binary_path,
                "config_dir": adapter.config_dir,
                "version": adapter.version,
            }
            if adapter.default_model:
                entry["model"] = adapter.default_model
            if adapter.default_provider:
                entry["provider"] = adapter.default_provider
            if adapter.mcp_servers:
                entry["mcp_servers"] = adapter.mcp_servers
            connections[adapter.adapter_id] = entry

        current.setdefault("connections", {})
        for adapter_id, entry in connections.items():
            current["connections"].setdefault(adapter_id, {})
            current["connections"][adapter_id].update(entry)

        save_settings(current)
    return {
        "applied_count": len(connections),
        "adapter_ids": list(connections.keys()),
    }

@router.get("/api/connections/verify", response_model=ExtensibleResponse)
def verify_connections(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    """Run a one-word prompt through each detected backend and report status."""
    from api.backend_verification import verify_all_backends

    return verify_all_backends()
