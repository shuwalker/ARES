"""Deep Research API endpoints — iterative Think→Search→Extract→Synthesize engine."""

from __future__ import annotations

from typing import Annotated, Any, Optional

from fastapi import APIRouter, Depends, Query

from ..request_context import RequestIdentity, require_identity, require_mutation_identity

router = APIRouter(prefix="/api/research", tags=["research"])

# Module-level handler — lazy-initialized on first request
_handler = None


def _get_handler():
    """Lazy-init the research handler singleton."""
    global _handler
    if _handler is None:
        from api.research.handler import ResearchHandler
        _handler = ResearchHandler()
    return _handler


@router.post("/start")
def start_research(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    """Start a deep research task.

    Body: { "query": str, "max_time"?: int, "category"?: str, "session_id"?: str }
    Returns: { session_id, status, query }
    """
    query = (payload.get("query") or "").strip()
    if not query:
        from ..errors import CoreApiError
        raise CoreApiError(400, "query is required")

    max_time = min(600, max(30, int(payload.get("max_time", 300))))
    category = payload.get("category")  # optional: product, comparison, howto, factcheck
    session_id = payload.get("session_id") or f"research-{id(payload)}"

    handler = _get_handler()
    return handler.start_research(
        session_id=session_id,
        query=query,
        max_time=max_time,
        category=category,
    )


@router.get("/status")
def research_status(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1),
):
    """Get current research progress for a session."""
    handler = _get_handler()
    status = handler.get_status(session_id)
    if status is None:
        return {"status": "not_found"}
    return status


@router.get("/result")
def research_result(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1),
):
    """Get the completed research report."""
    handler = _get_handler()
    result = handler.get_result(session_id)
    sources = handler.get_sources(session_id)
    status = handler.get_status(session_id)

    return {
        "session_id": session_id,
        "status": status.get("status", "unknown") if status else "not_found",
        "result": result,
        "sources": sources or [],
    }


@router.post("/cancel")
def cancel_research(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    """Cancel a running research task."""
    session_id = (payload.get("session_id") or "").strip()
    if not session_id:
        from ..errors import CoreApiError
        raise CoreApiError(400, "session_id is required")

    handler = _get_handler()
    success = handler.cancel_research(session_id)
    return {"cancelled": success}


@router.delete("/result")
def clear_research_result(
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    session_id: str = Query(min_length=1),
):
    """Clear a persisted research result."""
    handler = _get_handler()
    handler.clear_result(session_id)
    return {"cleared": True}


__all__ = ["router"]