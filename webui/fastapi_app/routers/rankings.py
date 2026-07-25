"""Worker effectiveness rankings (Companion technical intelligence)."""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict, Field

from api.worker_rankings import RankingError, list_rankings, record_evaluation
from ..errors import CoreApiError
from ..request_context import RequestIdentity, require_identity

router = APIRouter(tags=["workers"])


class EvaluationIn(BaseModel):
    model_config = ConfigDict(extra="forbid")

    worker_id: str = Field(min_length=1, max_length=128)
    metrics: dict[str, float] = Field(default_factory=dict)
    session_id: str | None = Field(default=None, max_length=128)
    task_kind: str | None = Field(default=None, max_length=64)
    notes: str | None = Field(default=None, max_length=500)


@router.get("/api/workers/rankings")
def get_worker_rankings(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
) -> dict[str, Any]:
    try:
        return list_rankings(identity.profile)
    except RankingError as exc:
        raise CoreApiError(500, str(exc)) from exc


@router.post("/api/workers/evaluations")
def post_worker_evaluation(
    body: EvaluationIn,
    identity: Annotated[RequestIdentity, Depends(require_identity)],
) -> dict[str, Any]:
    try:
        event = record_evaluation(
            identity.profile,
            worker_id=body.worker_id,
            metrics=body.metrics,
            session_id=body.session_id,
            task_kind=body.task_kind,
            notes=body.notes,
        )
        return {"ok": True, "evaluation": event}
    except RankingError as exc:
        raise CoreApiError(400, str(exc)) from exc
