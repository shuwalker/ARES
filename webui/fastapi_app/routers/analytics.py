"""Usage analytics and project-status dashboard routes."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query

from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_identity


router = APIRouter(tags=["analytics"])


@router.get("/api/insights")
def insights(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    days: int = Query(default=30, ge=1, le=365),
):
    from api.insights import build_insights

    with profile_scope(identity.profile):
        return build_insights(days)


@router.get("/api/project-os/dashboard")
def project_os_dashboard(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    board: str = "",
):
    from api.project_os import build_project_dashboard

    with profile_scope(identity.profile):
        try:
            return build_project_dashboard(board=board)
        except ValueError as exc:
            raise CoreApiError(400, str(exc)) from exc


@router.get("/api", include_in_schema=False)
def api_root(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    """Keep the reserved API root out of the frontend SPA catch-all."""

    raise CoreApiError(404, "API endpoint not found")


__all__ = ["router"]
