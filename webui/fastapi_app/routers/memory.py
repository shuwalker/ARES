"""Local Profile memory and project-context API."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_identity, require_mutation_identity
from ..schemas import MemoryWrite


router = APIRouter(prefix="/api/memory", tags=["memory"])


@router.get("")
def get_memory(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = "",
    workspace: str = "",
):
    from api.config import get_config
    from api.context_store import maybe_reindex_project_context
    from api.memory_store import read_memory, resolve_project_context_workspace

    with profile_scope(identity.profile):
        result = read_memory(session_id=session_id, workspace=workspace)
        try:
            config_data = get_config()
            workspace_path = resolve_project_context_workspace(session_id=session_id, workspace=workspace)
            maybe_reindex_project_context(workspace_path, config_data=config_data)
        except Exception:
            pass
        return result


@router.get("/context-store/status")
def context_store_status(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    from api.context_store import store_status

    with profile_scope(identity.profile):
        return store_status()


@router.post("/context-store/reindex")
def context_store_reindex(
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.config import get_config
    from api.context_store import is_enabled, reindex_source, store_status
    from api.memory_store import read_active_project_context, read_memory, resolve_project_context_workspace

    with profile_scope(identity.profile):
        config_data = get_config()
        if not is_enabled(config_data):
            raise CoreApiError(400, "Context Store is disabled. Enable it in Settings before reindexing.")
        memory = read_memory()
        sections = (
            ("memory", "memory", memory.get("memory_path", ""), memory.get("memory", "")),
            ("user", "user", memory.get("user_path", ""), memory.get("user", "")),
            ("soul", "soul", memory.get("soul_path", ""), memory.get("soul", "")),
        )
        for source_key, source_type, path, content in sections:
            if path and content:
                reindex_source(source_key, source_type, path, content, config_data=config_data)
        workspace_path = resolve_project_context_workspace()
        if workspace_path is not None:
            context = read_active_project_context(workspace_path)
            if context.get("path"):
                reindex_source(
                    f"project_context:{context['path']}", "project_context",
                    context["path"], context.get("content") or "",
                    config_data=config_data, mtime=context.get("mtime"),
                )
        return store_status()


@router.get("/context-store/search")
def context_store_search(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    query: str = "",
    top_k: int = 5,
):
    """Semantic search over the Context Store; returns ranked matching chunks."""
    from api.config import get_config
    from api.context_store import is_enabled, retrieve

    query = (query or "").strip()
    if not query:
        raise CoreApiError(400, "query is required")
    # Clamp explicitly: `top_k or 5` would turn an explicit 0 into the default.
    top_k = 5 if top_k is None else max(1, min(int(top_k), 50))

    with profile_scope(identity.profile):
        config_data = get_config()
        if not is_enabled(config_data):
            raise CoreApiError(400, "Context Store is disabled. Enable it in Settings before searching.")
        chunks = retrieve(query, top_k=top_k, config_data=config_data)
        return {
            "query": query,
            "results": [
                {
                    "text": chunk.text,
                    "source_key": chunk.source_key,
                    "source_type": chunk.source_type,
                    "path": chunk.path,
                    "heading": chunk.heading,
                    "distance": chunk.distance,
                }
                for chunk in chunks
            ],
        }


@router.post("/write")
def update_memory(
    payload: MemoryWrite,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.memory_store import MemoryStoreError, write_memory

    try:
        with profile_scope(identity.profile):
            return write_memory(payload.section, payload.content)
    except MemoryStoreError as exc:
        raise CoreApiError(exc.status_code, str(exc)) from exc


__all__ = ["router"]
