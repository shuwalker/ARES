"""Messaging gateway status and lifecycle controls."""

from typing import Annotated

from fastapi import APIRouter, Depends

from ..request_context import RequestIdentity, require_identity


router = APIRouter(prefix="/api/gateway", tags=["gateway"])


@router.get("/status")
def gateway_status(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.gateway_status import gateway_status_payload

    return gateway_status_payload()


__all__ = ["router"]
