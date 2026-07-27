"""Library collections — connect and read folder-backed knowledge sources."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, Query

from ..errors import CoreApiError
from ..request_context import (
    RequestIdentity,
    profile_scope,
    require_identity,
    require_mutation_identity,
)
from ..schemas import LibraryCollectionAdd, LibraryCollectionRemove, LibraryCollectionRename


router = APIRouter(prefix="/api/library", tags=["library"])


def _run(operation, identity: RequestIdentity, *args, **kwargs):
    from api.library_store import LibraryError

    try:
        with profile_scope(identity.profile):
            return operation(*args, **kwargs)
    except LibraryError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except (OSError, PermissionError) as exc:
        raise CoreApiError(400, str(exc)) from exc


@router.get("/agent-sources")
def agent_sources(identity: Annotated[RequestIdentity, Depends(require_identity)]):
    """What agent history exists on this machine and how much ARES can read.

    Lives under System in the UI (memory infrastructure), not Library: this is
    how knowledge is indexed, not the knowledge itself.
    """
    from api.agent_sources import discover_agent_sources

    return _run(discover_agent_sources, identity)


@router.get("/collections")
def get_collections(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    stats: bool = Query(default=True),
):
    from api.library_store import list_collections

    return _run(list_collections, identity, include_stats=stats)


@router.post("/collections/add")
def add_collection(
    payload: LibraryCollectionAdd,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.library_store import add_collection as add

    return _run(add, identity, payload.path, payload.label, payload.kind)


@router.post("/collections/remove")
def remove_collection(
    payload: LibraryCollectionRemove,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.library_store import remove_collection as remove

    return _run(remove, identity, payload.collection_id)


@router.post("/collections/rename")
def rename_collection(
    payload: LibraryCollectionRename,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.library_store import rename_collection as rename

    return _run(rename, identity, payload.collection_id, payload.label)


@router.get("/browse")
def browse_collection(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    collection_id: str = Query(min_length=1, max_length=256),
    path: str = Query(default=".", max_length=4096),
):
    from api.library_store import browse

    return _run(browse, identity, collection_id, path)


@router.get("/item")
def read_collection_item(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    collection_id: str = Query(min_length=1, max_length=256),
    path: str = Query(min_length=1, max_length=4096),
):
    from api.library_store import read_item

    return _run(read_item, identity, collection_id, path)
