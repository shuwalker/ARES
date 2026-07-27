"""Optional local email integration endpoints."""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query

from ..errors import CoreApiError
from ..request_context import RequestIdentity, require_identity, require_mutation_identity


router = APIRouter(prefix="/api/email", tags=["email"])


def _run(operation, *args):
    from api.email_service import EmailServiceError

    try:
        return operation(*args)
    except EmailServiceError as exc:
        raise CoreApiError(exc.status_code, str(exc)) from exc


@router.get("/unread")
def unread(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    limit: int = Query(default=20, ge=1, le=50),
):
    from api.email_service import unread_messages
    return _run(unread_messages, limit)


@router.get("/all")
def all_mail(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    limit: int = Query(default=200, ge=1, le=500),
):
    from api.email_service import all_messages
    return _run(all_messages, limit)


@router.get("/message")
def message(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    id: str = Query(min_length=1, max_length=64),
):
    from api.email_service import message_detail
    return _run(message_detail, id)


@router.get("/classify")
def classify(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    id: str = Query(min_length=1, max_length=64),
):
    from api.email_service import classify_message
    return _run(classify_message, id)


@router.get("/thread")
def thread(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    id: str = Query(min_length=1, max_length=64),
):
    from api.email_service import message_thread
    return _run(message_thread, id)


@router.post("/draft")
def draft(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.email_service import draft_reply
    return _run(draft_reply, payload)


@router.post("/clean")
def clean(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.email_service import clean_inbox
    return _run(clean_inbox, payload)


@router.post("/move")
def move(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.email_service import move_message
    return _run(move_message, payload)


@router.post("/mark_read")
def mark_read(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.email_service import mark_message_read
    return _run(mark_message_read, payload)


@router.post("/save_nas")
def save_nas(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.email_service import save_message_to_nas
    return _run(save_message_to_nas, payload)


__all__ = ["router"]
