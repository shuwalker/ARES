"""Master-Worker Dispatch endpoints.

Exposes the ``DispatchService`` orchestration loop through HTTP without touching
the existing chat runtime.  The old ``/api/chat/start`` flow is untouched and
acts as the production fallback.

Routes
------
POST /api/dispatch/turn          – full orchestrate→execute→evaluate cycle
POST /api/dispatch/approve       – approve a gated plan step
POST /api/dispatch/reject        – reject a gated plan step
GET  /api/dispatch/plan/{plan_id} – inspect a plan's current state
"""

from __future__ import annotations

import logging
from typing import Annotated, Any

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict, Field

from ..errors import CoreApiError
from ..request_context import (
    RequestIdentity,
    profile_scope,
    require_identity,
    require_mutation_identity,
)

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/dispatch", tags=["dispatch"])


# ── Request schemas ─────────────────────────────────────────────────────────

class DispatchTurnRequest(BaseModel):
    """Payload for a single dispatch turn."""

    model_config = ConfigDict(extra="forbid", strict=True)

    message: str = Field(min_length=1, max_length=100_000)
    conversation_id: str = Field(min_length=1, max_length=256)
    local_only_mode: bool = False
    si_name: str = "Leo"
    owner_name: str = "User"


class DispatchApprovalRequest(BaseModel):
    """Payload for approving a gated step."""

    model_config = ConfigDict(extra="forbid", strict=True)

    plan_id: str = Field(min_length=1, max_length=256)
    step_id: str = Field(min_length=1, max_length=256)


class DispatchRejectionRequest(BaseModel):
    """Payload for rejecting a gated step."""

    model_config = ConfigDict(extra="forbid", strict=True)

    plan_id: str = Field(min_length=1, max_length=256)
    step_id: str = Field(min_length=1, max_length=256)
    reason: str = "User rejected step"


# ── Endpoints ───────────────────────────────────────────────────────────────

@router.post("/turn")
def dispatch_turn(
    payload: DispatchTurnRequest,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
) -> dict[str, Any]:
    """Execute a full Master-Worker dispatch turn.

    Orchestrates a plan, assigns a worker, executes, evaluates output through
    the 6-check verification pipeline, and records the result to the turn
    journal.  If a step requires human approval the response will carry
    ``status: "awaiting_approval"`` and no worker is dispatched until
    ``/api/dispatch/approve`` is called.
    """
    from api.dispatch_service import get_dispatch_service

    svc = get_dispatch_service()

    with profile_scope(identity.profile):
        result = svc.dispatch_turn(
            user_message=payload.message,
            conversation_id=payload.conversation_id,
            local_only_mode=payload.local_only_mode,
            si_name=payload.si_name,
            owner_name=payload.owner_name,
        )

    if result.get("error"):
        raise CoreApiError(
            int(result.get("_status", 500)),
            str(result["error"]),
        )
    return result


@router.post("/approve")
def approve_step(
    payload: DispatchApprovalRequest,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
) -> dict[str, Any]:
    """Approve an awaiting-approval step so the next dispatch turn executes it."""
    from api.dispatch_service import get_dispatch_service

    svc = get_dispatch_service()

    with profile_scope(identity.profile):
        result = svc.approve_step(
            plan_id=payload.plan_id,
            step_id=payload.step_id,
        )

    if result.get("status") == "not_found":
        raise CoreApiError(404, result.get("error", "Not found"))
    return result


@router.post("/reject")
def reject_step(
    payload: DispatchRejectionRequest,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
) -> dict[str, Any]:
    """Reject a gated step, marking the plan as failed."""
    from api.dispatch_service import get_dispatch_service

    svc = get_dispatch_service()

    with profile_scope(identity.profile):
        result = svc.reject_step(
            plan_id=payload.plan_id,
            step_id=payload.step_id,
            reason=payload.reason,
        )

    if result.get("status") == "not_found":
        raise CoreApiError(404, result.get("error", "Not found"))
    return result


@router.get("/plan/{plan_id}")
def get_plan(
    plan_id: str,
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
) -> dict[str, Any]:
    """Inspect the current state of a dispatch plan."""
    from core.si.orchestrator import load_plan

    plan = load_plan(plan_id)
    if plan is None:
        raise CoreApiError(404, f"Plan {plan_id} not found")

    return {
        "plan_id": plan.plan_id,
        "status": plan.status.value if hasattr(plan.status, "value") else str(plan.status),
        "intent": plan.intent,
        "steps": [
            {
                "step_id": s.step_id,
                "description": s.description,
                "status": s.status.value if hasattr(s.status, "value") else str(s.status),
                "assigned_worker": s.assigned_worker,
                "result": s.result,
            }
            for s in plan.steps
        ],
    }


@router.post("/budget/set")
def set_budget(
    worker_id: str,
    daily_limit: float,
    monthly_limit: float,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
) -> dict[str, Any]:
    """Set budget limits for a worker."""
    from api.budget_service import set_budget_limit

    set_budget_limit(worker_id, daily_limit, monthly_limit)
    return {
        "worker_id": worker_id,
        "daily_limit": daily_limit,
        "monthly_limit": monthly_limit,
        "status": "set",
    }


@router.get("/budget/status/{worker_id}")
def get_budget_status(
    worker_id: str,
    identity: Annotated[RequestIdentity, Depends(require_identity)],
) -> dict[str, Any]:
    """Check budget status for a worker."""
    from api.budget_service import check_budget, get_budget_limit, get_daily_spend, get_monthly_spend

    limit = get_budget_limit(worker_id)
    if limit is None:
        return {"worker_id": worker_id, "status": "no_limit_set"}

    daily_spent = get_daily_spend(worker_id)
    monthly_spent = get_monthly_spend(worker_id)

    can_exec = check_budget(worker_id)

    return {
        "worker_id": worker_id,
        "daily_limit": limit.daily_limit,
        "daily_spent": daily_spent,
        "daily_percent": (daily_spent / limit.daily_limit * 100) if limit.daily_limit > 0 else 0,
        "monthly_limit": limit.monthly_limit,
        "monthly_spent": monthly_spent,
        "monthly_percent": (monthly_spent / limit.monthly_limit * 100) if limit.monthly_limit > 0 else 0,
        "can_execute": can_exec["can_execute"],
        "warning": can_exec.get("warning"),
    }


__all__ = ["router"]
