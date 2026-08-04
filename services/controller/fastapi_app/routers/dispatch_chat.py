"""Chat integration with dispatch system.

Routes chat messages through dispatch orchestration instead of direct worker.
Provides endpoints that work with existing frontend (no changes needed).

Two modes:
1. Explicit mode: POST /api/dispatch/chat/start (opt-in dispatch routing)
2. Transparent mode: Set ARES_CHAT_VIA_DISPATCH=1 to route all chat through dispatch
"""

from __future__ import annotations

import logging
from typing import Annotated, Any
from uuid import uuid4

from fastapi import APIRouter, Depends, Query

from api.dispatch_service import DispatchService
from fastapi_app.errors import CoreApiError
from fastapi_app.request_context import RequestIdentity, require_identity
from fastapi_app.schemas import ChatStartResponse

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/api/dispatch", tags=["dispatch-chat"])


def _init_dispatch_service() -> DispatchService:
    """Initialize dispatch service."""
    return DispatchService()


def _dispatch_to_streaming_events(
    session_id: str,
    result: dict[str, Any]
) -> list[dict[str, Any]]:
    """Convert dispatch result to streaming event format (NDJSON).

    Translates the batch dispatch response into the streaming format
    that the frontend WebSocket subscriber expects.
    """
    events: list[dict[str, Any]] = []

    if result.get("status") == "paused_budget_limit":
        # Budget exceeded — return error event
        events.append({
            "event": "error",
            "data": {
                "error": f"Budget limit exceeded: {result.get('reason', 'unknown')}"
            },
            "terminal": True,
        })
    elif result.get("status") == "step_completed":
        # Successful execution — convert output to token events
        output = result.get("output", "")
        if output:
            # Split output into token-sized chunks for realistic streaming
            for chunk in _chunk_output(output):
                events.append({
                    "event": "token",
                    "data": {"text": chunk},
                })

        # Add cost information as a warning
        if cost := result.get("cost_usd"):
            events.append({
                "event": "warning",
                "data": {"message": f"Cost: ${cost:.4f} | Worker: {result.get('assigned_worker')}"},
            })

        # Final done event with plan metadata
        events.append({
            "event": "done",
            "data": {
                "session": {"id": session_id},
                "plan_id": result.get("plan_id"),
                "assigned_worker": result.get("assigned_worker"),
                "evaluation": result.get("evaluation"),
            },
            "terminal": True,
        })
    else:
        # Unknown status
        events.append({
            "event": "error",
            "data": {"error": f"Dispatch error: {result.get('status')}"},
            "terminal": True,
        })

    return events


def _chunk_output(text: str, chunk_size: int = 50) -> list[str]:
    """Split output into realistic token-sized chunks for streaming display."""
    if not text:
        return []
    chunks = []
    for i in range(0, len(text), chunk_size):
        chunks.append(text[i : i + chunk_size])
    return chunks


@router.post("/chat/start", response_model=ChatStartResponse)
def dispatch_chat_start(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(..., min_length=1, max_length=256),
    message: str = Query(..., min_length=1),
    model: str = Query(default="", max_length=256),
    model_provider: str = Query(default="", max_length=256),
    connection_id: str = Query(default="", max_length=256),
    workspace: str = Query(default="", max_length=4096),
    profile: str = Query(default="default", max_length=256),
    personality: str = Query(default="", max_length=256),
) -> ChatStartResponse:
    """Start a chat turn through dispatch orchestration.

    Routes message through dispatch system:
    1. Orchestrator — classifies intent, creates execution plan
    2. Budget check — verifies worker can execute (daily/monthly limits)
    3. Worker dispatch — assigns to best available worker (Jaeger, Claude, Hermes, etc.)
    4. Evaluator — 6 safety checks on response (secrets, harmful content, syntax, etc.)
    5. Cost recording — LiteLLM tracks spend per model

    Returns stream_id that frontend uses to subscribe to WebSocket for response.
    **Compatible with existing frontend — no UI changes needed.**

    Query the same `/api/chat/stream?stream_id=...` WebSocket endpoint to receive
    the response as streaming events (token, warning, done).
    """
    try:
        # Create unique stream_id for this turn
        stream_id = f"dispatch-{uuid4().hex[:16]}"

        logger.info(
            "Dispatch chat: session=%s msg_len=%d model=%s",
            session_id,
            len(message),
            model or "auto",
        )

        # Execute through dispatch system (orchestrator → budget → worker → evaluator)
        dispatch_service = _init_dispatch_service()
        result = dispatch_service.dispatch_turn(
            user_message=message,
            conversation_id=session_id,
        )

        # Store streaming events for WebSocket subscriber to read
        _store_dispatch_events(stream_id, session_id, result)

        # Return same format as /api/chat/start — frontend doesn't know it's dispatch
        return ChatStartResponse(
            stream_id=stream_id,
            session_id=session_id,
            title=None,
        )

    except ValueError as e:
        raise CoreApiError(400, str(e)) from e
    except Exception as e:
        logger.error("Dispatch chat failed: %s", e, exc_info=True)
        raise CoreApiError(500, f"Dispatch failed: {str(e)}") from e


def _store_dispatch_events(stream_id: str, session_id: str, result: dict[str, Any]) -> None:
    """Store dispatch result for WebSocket subscriber to replay.

    Stores events in turn journal so the stream subscriber can retrieve them
    when the frontend requests /api/chat/stream with this stream_id.
    """
    try:
        from api.config import register_stream_owner
        from api.turn_journal import append_turn_journal_event

        # Register this stream as belonging to this session
        register_stream_owner(stream_id, session_id)

        # Store events in turn journal
        events = _dispatch_to_streaming_events(session_id, result)
        for event in events:
            try:
                append_turn_journal_event(
                    session_id=session_id,
                    event={
                        "stream_id": stream_id,
                        "event_type": event.get("event", "unknown"),
                        "data": event.get("data", {}),
                        "terminal": event.get("terminal", False),
                    }
                )
            except Exception as e:
                logger.warning("Failed to store event: %s", e)

        logger.debug("Stored dispatch events: stream_id=%s events=%d", stream_id, len(events))
    except Exception as e:
        logger.error("Failed to store dispatch events: %s", e)
