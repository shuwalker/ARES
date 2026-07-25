"""Human approval and clarification request contracts."""

from typing import Annotated

from fastapi import APIRouter, Depends, Query, Request, Response

from ..errors import CoreApiError
from ..request_context import RequestIdentity, require_identity, require_mutation_identity
from ..schemas import ApprovalResponse, ClarifyResponse


router = APIRouter(prefix="/api", tags=["interactions"])


def _require_loopback(request: Request) -> None:
    host = request.client.host if request.client else ""
    if host not in {"127.0.0.1", "::1", "testclient"}:
        raise CoreApiError(403, "test injection is loopback-only")


@router.get("/approval/pending")
def approval_pending(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
):
    from api.route_approvals import pending_snapshot

    return pending_snapshot(session_id)


@router.post("/approval/respond")
def approval_respond(
    payload: ApprovalResponse,
    response: Response,
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.route_approvals import respond_approval

    if not payload.session_id.strip():
        raise CoreApiError(400, "session_id is required")
    result, status = respond_approval(payload.session_id, payload.approval_id, payload.choice)
    response.status_code = status
    return result


@router.get("/approval/inject_test")
def inject_approval(
    request: Request,
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
    pattern_key: str = Query(default="test_pattern", max_length=512),
    command: str = Query(default="rm -rf /tmp/test", max_length=4096),
):
    from api.route_approvals import submit_pending

    _require_loopback(request)
    submit_pending(
        session_id,
        {
            "command": command,
            "pattern_key": pattern_key,
            "pattern_keys": [pattern_key],
            "description": "test pattern",
        },
    )
    return {"ok": True, "session_id": session_id}


@router.get("/clarify/pending")
def clarify_pending(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
):
    from api.clarify import get_pending

    return {"pending": get_pending(session_id)}


@router.post("/clarify/respond")
def clarify_respond(
    payload: ClarifyResponse,
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.clarify import resolve_clarify, resolve_clarify_by_id

    if not payload.session_id.strip():
        raise CoreApiError(400, "session_id is required")
    response = str(payload.response or payload.answer or payload.choice or "").strip()
    if not response:
        raise CoreApiError(400, "response is required")
    accepted = (
        resolve_clarify_by_id(payload.session_id, payload.clarify_id, response)
        if payload.clarify_id
        else bool(resolve_clarify(payload.session_id, response, resolve_all=False))
    )
    if not accepted:
        raise CoreApiError(
            409,
            "Clarification prompt expired or not found. The agent may have already proceeded.",
            context={"ok": False, "stale": True},
        )
    return {"ok": True, "response": response}


@router.get("/clarify/inject_test")
def inject_clarification(
    request: Request,
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
    question: str = Query(default="Which option?", max_length=4096),
    choices: list[str] = Query(default=[]),
):
    from api.clarify import submit_pending

    _require_loopback(request)
    submit_pending(
        session_id,
        {
            "question": question,
            "choices_offered": choices,
            "session_id": session_id,
            "kind": "clarify",
        },
    )
    return {"ok": True, "session_id": session_id}


__all__ = ["router"]
