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
        items.append({
            "id": name,
            "name": getattr(backend, "name", name),
            "available": backend.is_available(),
            "kind": getattr(backend, "kind", "agent"),
            "description": getattr(backend, "description", ""),
            "models": getattr(backend, "models", lambda: [])() if callable(getattr(backend, "models", None)) else [],
        })
    return {"backends": sorted(items, key=lambda x: (not x["available"], x["id"]))}
