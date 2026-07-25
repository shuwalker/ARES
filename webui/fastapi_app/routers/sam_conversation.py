import asyncio
import logging
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException

from ..dependencies import get_realtime_service
from ..realtime import RealtimeService
from ..schemas import ChatStart, ChatStartResponse
from ..request_context import RequestIdentity, profile_scope, require_mutation_identity

router = APIRouter(prefix="/api/sam-conversation", tags=["sam-conversation"])
logger = logging.getLogger(__name__)

@router.post("/compress")
async def compress_memory(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
) -> dict[str, Any]:
    """
    Adapter endpoint for the SAM ConversationEngine to request memory compression.
    Delegates to the Python memory compressor.
    """
    with profile_scope(identity.profile):
        try:
            from fastapi_app.memory.compressor import run_compression
            session_id = payload.get("session_id")
            if not session_id:
                raise ValueError("session_id is required")
            result = await asyncio.to_thread(run_compression, session_id)
            return {"status": "success", "message": "Memory compressed by Python backend.", "result": result}
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        except Exception as exc:
            logger.exception("SAM memory compression failed")
            raise HTTPException(status_code=500, detail="Memory compression failed.") from exc

@router.post("/chat", response_model=ChatStartResponse)
async def sam_chat(
    payload: ChatStart,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[RealtimeService, Depends(get_realtime_service)],
) -> dict[str, Any]:
    """
    Adapter endpoint for SAM ConversationEngine to start a chat inference session
    using a specific LLM adapter (e.g. hermes_local, ollama_local).
    """
    with profile_scope(identity.profile):
        try:
            return await service.start_chat(payload, profile=identity.profile)
        except HTTPException:
            raise
        except Exception:
            # CoreApiError and adapter failures are handled by the application
            # exception boundary. Do not replace them with raw exception text.
            raise

__all__ = ["router"]
