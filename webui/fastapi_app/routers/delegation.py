"""Delegate discrete tasks to an execution backend and poll their Run status."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_identity, require_mutation_identity
from ..schemas import DelegationCreate

router = APIRouter(prefix="/api/delegation", tags=["delegation"])


@router.post("/tasks")
def create_delegation(
    payload: DelegationCreate,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    """Create a delegated task and start it on a background thread (Queued)."""
    prompt = (payload.prompt or "").strip()
    backend = (payload.backend or "").strip()
    if not prompt:
        raise CoreApiError("prompt is required", status_code=400)
    if not backend:
        raise CoreApiError("backend is required", status_code=400)

    from api.delegation_runner import delegate

    with profile_scope(identity.profile):
        task = delegate(
            prompt=prompt,
            backend=backend,
            model=payload.model,
            provider=payload.provider,
        )
    return task


@router.get("/tasks/{task_id}")
def get_delegation(
    task_id: str,
    identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    """Return the current Run status/result of a delegated task."""
    from api.delegation_tasks import get_task

    with profile_scope(identity.profile):
        task = get_task(task_id)
    if task is None:
        raise CoreApiError("task not found", status_code=404)
    return task


@router.get("/tasks")
def list_delegations(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    from api.delegation_tasks import list_tasks

    with profile_scope(identity.profile):
        return {"tasks": list_tasks()}


__all__ = ["router"]
