"""Flat registry of ARES agnostic backend adapters.

Mirrors api/backends/router.py for the React UI.
"""

from typing import Annotated

from fastapi import APIRouter, Depends

from api.backends.router import get_router

from ..dependencies import get_core_service
from ..request_context import RequestIdentity, require_identity
from ..services import AresCoreService

router = APIRouter(prefix="/api/backends", tags=["backends"])


@router.get("")
def list_backends(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    registry = get_router()
    items = []
    for name, backend in registry.list_all().items():
        inventory = None
        inv_fn = getattr(backend, "inventory", None)
        if callable(inv_fn):
            try:
                inventory = inv_fn()
            except Exception:
                inventory = None
        models = []
        if isinstance(inventory, dict):
            models = list(inventory.get("models") or [])
        elif callable(getattr(backend, "models", None)):
            try:
                models = backend.models() or []
            except Exception:
                models = []
        items.append({
            "id": name,
            "name": getattr(backend, "name", name),
            "available": backend.is_available(),
            "kind": getattr(backend, "kind", "agent"),
            "description": getattr(backend, "description", ""),
            "models": models,
            # Full catalog: models (local+cloud), transports, gateways, MCP —
            # including paths not currently selected for ARES execution.
            "inventory": inventory,
        })
    return {"backends": sorted(items, key=lambda x: (not x["available"], x["id"]))}
