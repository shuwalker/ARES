"""Private-safe local wiki endpoints."""

from __future__ import annotations

import asyncio
from typing import Annotated

from fastapi import APIRouter, Depends, Query

from api.wiki_store import WikiStoreError

from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_identity


router = APIRouter(prefix="/api/wiki", tags=["wiki"])


def _profile_call(profile, operation, *args):
    with profile_scope(profile):
        return operation(*args)


async def _call(identity, operation, *args):
    try:
        return await asyncio.to_thread(_profile_call, identity.profile, operation, *args)
    except WikiStoreError as exc:
        raise CoreApiError(exc.status_code, str(exc)) from exc


@router.get("/status")
async def wiki_status(identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.wiki_store import status

    return await _call(identity, status)


@router.get("/browse")
async def wiki_browse(identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.wiki_store import browse

    return await _call(identity, browse)


@router.get("/page")
async def wiki_page(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    path: str = Query(min_length=1, max_length=2048),
):
    from api.wiki_store import read_page

    return await _call(identity, read_page, path)
