"""Background work, side-question, goal, and acknowledgement controls."""

from __future__ import annotations

import asyncio
import uuid
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Response

from ..dependencies import get_realtime_service
from ..errors import CoreApiError
from ..realtime import RealtimeService
from ..request_context import RequestIdentity, profile_scope, require_mutation_identity
from ..schemas import ChatStart


router = APIRouter(tags=["controls"])


def _session(session_id: str, profile: str | None):
    from api.models import get_session
    from api.profiles import _profiles_match

    if not session_id:
        raise CoreApiError(400, "session_id is required")
    try:
        session = get_session(session_id)
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc
    if profile and not _profiles_match(getattr(session, "profile", None), profile):
        raise CoreApiError(404, "Session not found")
    if getattr(session, "read_only", False) or getattr(session, "is_subagent", False):
        raise CoreApiError(400, "This conversation is read-only")
    return session


async def _new_child_run(
    parent,
    message: str,
    *,
    profile: str | None,
    service: RealtimeService,
    title_prefix: str,
    copy_messages: bool,
):
    from api.models import new_session

    child = new_session(
        workspace=parent.workspace,
        model=parent.model,
        model_provider=getattr(parent, "model_provider", None),
        profile=getattr(parent, "profile", None),
    )
    child.title = f"{title_prefix}: {message[:60]}"
    if copy_messages:
        child.messages = list(parent.messages or [])
    child.save()
    result = await service.start_chat(
        ChatStart(
            session_id=child.session_id,
            message=message,
            model=child.model,
            model_provider=getattr(child, "model_provider", None),
            workspace=child.workspace,
            profile=getattr(child, "profile", None),
        ),
        profile=profile,
    )
    return child, result


async def _observe_background(
    parent_id: str,
    task_id: str,
    child_id: str,
    stream_id: str,
    service: RealtimeService,
    profile: str | None,
):
    from api.background import complete_background
    from api.models import Session

    answer = "(no answer produced)"
    try:
        subscription = service.chat_subscription(stream_id, profile=profile)
        if subscription is not None:
            try:
                while True:
                    event = await asyncio.to_thread(subscription.subscriber.get)
                    if event and event[0] in {"stream_end", "error", "cancel"}:
                        break
            finally:
                subscription.close()
        child = Session.load(child_id)
        for message in reversed((child.messages if child else None) or []):
            if not isinstance(message, dict):
                continue
            content = str(message.get("content") or "").strip()
            if message.get("role") == "assistant" and content and not message.get("_error"):
                answer = content
                break
    except Exception:
        answer = "(background task failed)"
    complete_background(parent_id, task_id, answer)


@router.post("/api/btw")
async def side_question(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[RealtimeService, Depends(get_realtime_service)],
):
    question = str(payload.get("question") or "").strip()
    if not question:
        raise CoreApiError(400, "question is required")
    with profile_scope(identity.profile):
        parent = _session(str(payload.get("session_id") or ""), identity.profile)
        child, result = await _new_child_run(
            parent,
            question,
            profile=identity.profile,
            service=service,
            title_prefix="btw",
            copy_messages=True,
        )
        from api.background import track_btw

        track_btw(parent.session_id, child.session_id, result["stream_id"], question)
    return {
        "stream_id": result["stream_id"],
        "session_id": child.session_id,
        "parent_session_id": parent.session_id,
    }


@router.post("/api/background")
async def background_task(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[RealtimeService, Depends(get_realtime_service)],
):
    prompt = str(payload.get("prompt") or "").strip()
    if not prompt:
        raise CoreApiError(400, "prompt is required")
    with profile_scope(identity.profile):
        parent = _session(str(payload.get("session_id") or ""), identity.profile)
        child, result = await _new_child_run(
            parent,
            prompt,
            profile=identity.profile,
            service=service,
            title_prefix="bg",
            copy_messages=False,
        )
        task_id = uuid.uuid4().hex[:8]
        from api.background import track_background

        track_background(parent.session_id, child.session_id, result["stream_id"], task_id, prompt)
    asyncio.create_task(
        _observe_background(
            parent.session_id,
            task_id,
            child.session_id,
            result["stream_id"],
            service,
            identity.profile,
        )
    )
    return {"task_id": task_id, "stream_id": result["stream_id"], "session_id": child.session_id}


@router.post("/api/goal")
async def goal_control(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[RealtimeService, Depends(get_realtime_service)],
):
    from api.config import PENDING_GOAL_CONTINUATION, STREAMS, STREAMS_LOCK
    from api.goals import goal_command_payload
    from api.profiles import get_ares_home_for_profile

    with profile_scope(identity.profile):
        session = _session(str(payload.get("session_id") or ""), identity.profile)
        stream_id = getattr(session, "active_stream_id", None)
        with STREAMS_LOCK:
            running = bool(stream_id and stream_id in STREAMS)
        profile_home = get_ares_home_for_profile(getattr(session, "profile", None))
        text = str(payload.get("args") or payload.get("text") or "")
        result = goal_command_payload(
            session.session_id,
            text,
            stream_running=running,
            profile_home=profile_home,
        )
        if not result.get("ok", True):
            status = 409 if result.get("error") == "agent_running" else 400
            raise CoreApiError(status, str(result.get("error") or "Goal update failed"), context=result)
        kickoff = str(result.get("kickoff_prompt") or "").strip()
        if kickoff:
            # The kickoff is the first goal-owned turn. Use the same one-shot
            # marker as automatic continuations so chat_runtime can pass the
            # explicit goal_related flag to every adapter implementation.
            PENDING_GOAL_CONTINUATION.add(session.session_id)
            try:
                stream = await service.start_chat(
                    ChatStart(
                        session_id=session.session_id,
                        message=kickoff,
                        model=payload.get("model") or session.model,
                        model_provider=payload.get("model_provider") or getattr(session, "model_provider", None),
                        workspace=payload.get("workspace") or session.workspace,
                        profile=getattr(session, "profile", None),
                    ),
                    profile=identity.profile,
                )
            except Exception:
                PENDING_GOAL_CONTINUATION.discard(session.session_id)
                raise
            result.update(stream)
    return result


@router.post("/api/bg-task-complete-ack")
def acknowledge_background_completion(
    payload: dict[str, Any],
    response: Response,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    with profile_scope(identity.profile):
        session = _session(str(payload.get("session_id") or ""), identity.profile)
    if str(payload.get("process_id") or "").strip():
        response.headers["Deprecation"] = "true"
    return {
        "ok": True,
        "session_id": session.session_id,
        "task_id": str(payload.get("task_id") or payload.get("process_id") or "").strip(),
        "noop": True,
    }


__all__ = ["router"]
