"""External notes drawer endpoints."""

from __future__ import annotations

import asyncio
from typing import Annotated

from fastapi import APIRouter, Depends, Query

from api.notes_store import NotesStoreError

from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_identity


router = APIRouter(prefix="/api/notes", tags=["notes"])


def _error(exc: NotesStoreError) -> CoreApiError:
    return CoreApiError(exc.status_code, str(exc))


def _profile_call(profile: str | None, operation, *args):
    with profile_scope(profile):
        return operation(*args)


@router.get("/sources")
def sources(identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.notes_store import list_sources

    with profile_scope(identity.profile):
        return list_sources()


@router.get("/search")
async def search(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    q: str = Query(default="", max_length=4096),
    source: str = Query(default="joplin", max_length=64),
    limit: int = Query(default=20, ge=1, le=50),
):
    from api.notes_store import search_notes

    try:
        return await asyncio.to_thread(
            _profile_call,
            identity.profile,
            search_notes,
            q,
            source,
            limit,
        )
    except NotesStoreError as exc:
        raise _error(exc) from exc


@router.get("/item")
async def item(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    id: str = Query(min_length=1, max_length=64),
    source: str = Query(default="joplin", max_length=64),
):
    from api.notes_store import get_note

    try:
        return await asyncio.to_thread(
            _profile_call,
            identity.profile,
            get_note,
            id,
            source,
        )
    except NotesStoreError as exc:
        raise _error(exc) from exc
