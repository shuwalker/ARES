"""Public conversation snapshots and authenticated share mutations."""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends
from fastapi.responses import JSONResponse

from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_mutation_identity


router = APIRouter(tags=["shares"])


@router.get("/api/share/{token}")
def public_share(token: str):
    from api.shares import load_share

    share = load_share(token)
    if not share:
        raise CoreApiError(404, "Shared conversation not found")
    return JSONResponse(
        {"share": share},
        headers={
            "Cache-Control": "no-store",
            "X-Robots-Tag": "noindex, nofollow",
        },
    )


def _share_session(session_id: str):
    from api.models import get_session

    if not session_id:
        raise CoreApiError(400, "session_id is required")
    try:
        return get_session(session_id)
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc


@router.post("/api/share/create")
def create_share(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_events import publish_session_list_changed
    from api.shares import create_or_refresh_share

    with profile_scope(identity.profile):
        session = _share_session(str(payload.get("session_id") or "").strip())
        try:
            metadata = create_or_refresh_share(session)
        except ValueError as exc:
            raise CoreApiError(400, str(exc)) from exc
        session.share_token = metadata["share_token"]
        session.share_created_at = metadata["share_created_at"]
        session.save(touch_updated_at=False)
        publish_session_list_changed(
            "session_share_create",
            profile=getattr(session, "profile", None),
            session_id=session.session_id,
        )
        return {
            "ok": True,
            "share": {
                "token": metadata["share_token"],
                "url": f"/share/{metadata['share_token']}",
                "title": metadata["share_title"],
                "message_count": metadata["share_message_count"],
                "created_at": metadata["share_created_at"],
                "updated_at": metadata["share_updated_at"],
            },
            "session": session.compact() | {"messages": list(session.messages or [])},
        }


@router.post("/api/share/revoke")
def revoke_session_share(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_events import publish_session_list_changed
    from api.shares import revoke_share

    with profile_scope(identity.profile):
        session = _share_session(str(payload.get("session_id") or "").strip())
        revoke_share(session)
        session.share_token = None
        session.share_created_at = None
        session.save(touch_updated_at=False)
        publish_session_list_changed(
            "session_share_revoke",
            profile=getattr(session, "profile", None),
            session_id=session.session_id,
        )
        return {
            "ok": True,
            "session": session.compact() | {"messages": list(session.messages or [])},
        }


__all__ = ["router"]
