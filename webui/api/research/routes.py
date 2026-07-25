"""ARES WebUI — Deep Research API routes.

Exposes the iterative research engine as endpoints:
  GET  /api/research/start   — start a research task
  POST /api/research/start   — start a research task (alt)
  GET  /api/research/status   — get current progress
  GET  /api/research/result   — get completed report
  POST /api/research/cancel   — cancel running research
  DEL  /api/research/result   — clear persisted result
"""

from __future__ import annotations

import logging

from api.helpers import bad, j

logger = logging.getLogger(__name__)

# Module-level handler singleton
_handler = None


def _get_handler():
    """Lazy-initialize the research handler."""
    global _handler
    if _handler is None:
        from api.research.handler import ResearchHandler
        _handler = ResearchHandler()
    return _handler


# ---------------------------------------------------------------------------
# Route handlers — registered via the ARES handler/parsed pattern
# ---------------------------------------------------------------------------

def handle_research_start_post(handler, parsed, body: dict) -> bool:
    """Start a deep research task."""
    query = (body.get("query") or "").strip()
    if not query:
        bad(handler, "query is required", status=400)
        return True

    max_time = min(600, max(30, int(body.get("max_time", 300))))
    category = body.get("category")  # optional: product, comparison, howto, factcheck
    session_id = body.get("session_id") or f"research-{id(body)}"

    rh = _get_handler()
    result = rh.start_research(
        session_id=session_id,
        query=query,
        max_time=max_time,
        category=category,
    )
    j(handler, result)
    return True


def handle_research_status_get(handler, parsed) -> bool:
    """Get current research status."""
    session_id = parsed.get("session_id") or parsed.get("session_id") or ""
    if not session_id:
        bad(handler, "session_id is required", status=400)
        return True

    rh = _get_handler()
    status = rh.get_status(session_id)
    if status is None:
        j(handler, {"status": "not_found"})
    else:
        j(handler, status)
    return True


def handle_research_result_get(handler, parsed) -> bool:
    """Get the completed research report."""
    session_id = parsed.get("session_id") or ""
    if not session_id:
        bad(handler, "session_id is required", status=400)
        return True

    rh = _get_handler()
    result = rh.get_result(session_id)
    sources = rh.get_sources(session_id)
    status = rh.get_status(session_id)

    j(handler, {
        "session_id": session_id,
        "status": status.get("status", "unknown") if status else "not_found",
        "result": result,
        "sources": sources or [],
    })
    return True


def handle_research_cancel_post(handler, parsed, body: dict) -> bool:
    """Cancel a running research task."""
    session_id = (body.get("session_id") or "").strip()
    if not session_id:
        bad(handler, "session_id is required", status=400)
        return True

    rh = _get_handler()
    success = rh.cancel_research(session_id)
    j(handler, {"cancelled": success})
    return True


def handle_research_result_delete(handler, parsed) -> bool:
    """Clear a persisted research result."""
    session_id = parsed.get("session_id") or ""
    if not session_id:
        bad(handler, "session_id is required", status=400)
        return True

    rh = _get_handler()
    rh.clear_result(session_id)
    j(handler, {"cleared": True})
    return True