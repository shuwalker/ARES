"""Process and agent health endpoints."""

from typing import Annotated

from fastapi import APIRouter, Depends, Query, Request, Response
from fastapi.responses import JSONResponse

from ..dependencies import get_core_service
from ..request_context import RequestIdentity, require_identity, require_mutation_identity
from ..schemas import AgentHealthResponse, HealthResponse
from ..services import AresCoreService


router = APIRouter(tags=["health"])


@router.get("/health", response_model=HealthResponse)
@router.get("/api/health", response_model=HealthResponse)
def health(
    request: Request,
    service: Annotated[AresCoreService, Depends(get_core_service)],
    deep: bool = Query(default=False),
):
    payload, status_code = service.health(deep=deep)
    payload["accept_loop"] = {
        "status": "ok",
        "server": "uvicorn",
        "requests_total": int(getattr(request.app.state, "requests_total", 0)),
        "last_request_at": float(getattr(request.app.state, "last_request_at", 0.0)),
    }
    return JSONResponse(payload, status_code=status_code)


@router.get("/api/health/agent", response_model=AgentHealthResponse)
def agent_health(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    return service.agent_health()


@router.post("/api/health/restart")
def restart_gateway(
    response: Response,
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.gateway_restart import restart_active_profile_gateway

    outcome = restart_active_profile_gateway()
    status = outcome.get("status")
    if status == "completed":
        return {"ok": True, "message": "Gateway service restarted successfully"}
    if status == "in_progress":
        return {"ok": True, "message": "Gateway service restart initiated (in progress)"}
    if status == "busy":
        response.status_code = 429
        return {"ok": False, "error": outcome.get("message", "Restart already in progress")}
    response.status_code = 500
    return {"ok": False, "error": outcome.get("message", "Internal error running restart")}
