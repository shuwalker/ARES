"""Conversation session endpoints used by the React client."""

from __future__ import annotations

import asyncio
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response

from ..dependencies import get_core_service
from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_identity, require_mutation_identity
from ..schemas import (
    SessionBranch,
    SessionArchive,
    SessionAnchorScene,
    SessionCreate,
    SessionConversationRounds,
    SessionCliImport,
    SessionHandoffSummary,
    SessionCompression,
    SessionDraftUpdate,
    SessionImportPayload,
    SessionMutation,
    SessionMove,
    SessionPin,
    SessionRename,
    SessionResponse,
    SessionsResponse,
    SessionToolsetsUpdate,
    SessionTitleRegenerate,
    SessionTruncate,
    SessionUpdate,
    SessionWorktreeRemove,
    SessionYoloUpdate,
)
from ..services import AresCoreService


router = APIRouter(prefix="/api", tags=["sessions"])


@router.get("/sessions", response_model=SessionsResponse)
def list_sessions(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
    exclude_hidden: bool = Query(default=False),
    include_archived: bool = Query(default=False),
):
    return service.sessions(
        profile=identity.profile,
        exclude_hidden=exclude_hidden,
        include_archived=include_archived,
    )


@router.get("/session", response_model=SessionResponse)
def get_session(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
    session_id: str = Query(default="", max_length=256),
    messages: bool = Query(default=True),
    msg_limit: int | None = Query(default=None, ge=1, le=10_000),
    msg_before: int | None = Query(default=None, ge=0),
    resolve_model: bool = Query(default=True),
):
    if not session_id.strip():
        raise CoreApiError(400, "session_id is required")
    kwargs = {
        "profile": identity.profile,
        "load_messages": messages,
        "message_limit": msg_limit,
    }
    if isinstance(service, AresCoreService):
        kwargs.update(message_before=msg_before, resolve_model=resolve_model)
    return service.session(session_id, **kwargs)


@router.post("/session/new", response_model=SessionResponse)
def create_session(
    request: SessionCreate,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    if request.prev_session_id and len(request.prev_session_id.strip()) == 0:
        raise CoreApiError(400, "prev_session_id must not be blank")
    return service.create_session(request, profile=identity.profile)


@router.get("/sessions/search")
def search_sessions(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    q: str = Query(default="", max_length=4096),
    content: bool = Query(default=True),
    depth: str = Query(default="5", max_length=16),
    all_profiles: bool = Query(default=False),
):
    from api.session_query import search_sessions as search

    try:
        parsed_depth = max(0, int(depth))
    except (TypeError, ValueError):
        parsed_depth = 5
    with profile_scope(identity.profile):
        return search(q, content_search=content, depth=parsed_depth, all_profiles=all_profiles)


@router.get("/session/export")
def export_session(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
    format: str = Query(default="json", pattern="^(json|html)$"),
    theme: str = Query(default="dark", max_length=64),
    palette: str = Query(default="", max_length=16_384),
):
    from api.session_query import export_session as export

    try:
        with profile_scope(identity.profile):
            payload, content_type, extension = export(
                session_id,
                profile=identity.profile,
                format=format,
                theme=theme,
                palette=palette,
            )
    except FileNotFoundError as exc:
        raise CoreApiError(404, str(exc)) from exc
    return Response(
        payload,
        media_type=content_type,
        headers={
            "Content-Disposition": f'attachment; filename="ares-{session_id}.{extension}"',
            "Cache-Control": "no-store",
        },
    )


@router.get("/session/lineage/report")
def lineage_report(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
):
    from api.agent_sessions import read_session_lineage_report
    from api.models import _active_state_db_path

    with profile_scope(identity.profile):
        report = read_session_lineage_report(_active_state_db_path(), session_id)
    if not report.get("found"):
        raise CoreApiError(404, "Session not found")
    return report


@router.get("/session/recovery/audit")
def recovery_audit(identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.config import SESSION_DIR
    from api.models import _active_state_db_path
    from api.session_recovery import audit_session_recovery

    with profile_scope(identity.profile):
        return audit_session_recovery(SESSION_DIR, state_db_path=_active_state_db_path())


@router.post("/session/recovery/repair-safe")
def recovery_repair(identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.config import SESSION_DIR
    from api.models import _active_state_db_path
    from api.session_recovery import repair_safe_session_recovery

    with profile_scope(identity.profile):
        result = repair_safe_session_recovery(SESSION_DIR, state_db_path=_active_state_db_path())
    if not result.get("clean"):
        raise CoreApiError(409, str(result.get("error") or "Session recovery requires manual review"), context=result)
    return result


@router.get("/session/status")
def session_status(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
):
    from api.session_ops import session_status as status

    try:
        with profile_scope(identity.profile):
            return status(session_id)
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc


@router.get("/session/usage")
def session_usage(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
):
    from api.session_ops import session_usage as usage

    try:
        with profile_scope(identity.profile):
            return usage(session_id)
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc


@router.get("/session/yolo")
def session_yolo(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
):
    from api.route_approvals import is_session_yolo_enabled

    return {"yolo_enabled": is_session_yolo_enabled(session_id)}


@router.get("/background/status")
def background_status(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
):
    from api.background import get_results

    return {"results": get_results(session_id)}


@router.get("/session/worktree/status")
def worktree_status(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
):
    from api.models import get_session as load_session
    from api.worktrees import worktree_status_for_session

    try:
        with profile_scope(identity.profile):
            session = load_session(session_id, metadata_only=True)
            return {"status": worktree_status_for_session(session)}
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc


def _mutable_session_id(session_id: str, profile: str | None = None) -> str:
    from api.session_access import session_is_subagent_view_only
    from api.models import get_session, is_safe_session_id
    from api.profiles import _profiles_match

    session_id = str(session_id or "").strip()
    if not session_id or not is_safe_session_id(session_id):
        raise CoreApiError(400, "Missing required field: session_id")
    if profile is not None:
        try:
            session = get_session(session_id, metadata_only=True)
        except KeyError as exc:
            raise CoreApiError(404, "Session not found") from exc
        if not _profiles_match(getattr(session, "profile", None), profile):
            raise CoreApiError(404, "Session not found")
    if session_is_subagent_view_only(session_id):
        raise CoreApiError(400, "Subagent sessions are view-only and cannot be modified from WebUI")
    return session_id


@router.post("/session/retry")
def retry_session(
    payload: SessionMutation,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_ops import retry_last

    session_id = _mutable_session_id(payload.session_id, identity.profile)
    try:
        with profile_scope(identity.profile):
            return {"ok": True, **retry_last(session_id)}
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc


@router.post("/session/undo")
def undo_session(
    payload: SessionMutation,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_ops import undo_last

    session_id = _mutable_session_id(payload.session_id, identity.profile)
    try:
        with profile_scope(identity.profile):
            return {"ok": True, **undo_last(session_id)}
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc


@router.post("/session/yolo")
def set_session_yolo(
    payload: SessionYoloUpdate,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.route_approvals import (
        disable_session_yolo,
        enable_session_yolo,
        resolve_gateway_approval,
    )

    session_id = _mutable_session_id(payload.session_id, identity.profile)
    enabled = payload.enabled
    if enabled:
        enable_session_yolo(session_id)
        resolve_gateway_approval(session_id, "once", resolve_all=True)
    else:
        disable_session_yolo(session_id)
    return {"ok": True, "yolo_enabled": enabled}


@router.get("/session/draft")
def get_draft(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
):
    from api.session_mutations import get_session_draft

    try:
        with profile_scope(identity.profile):
            return {"draft": get_session_draft(session_id)}
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc


@router.post("/session/draft")
def save_draft(
    payload: SessionDraftUpdate,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_mutations import save_session_draft

    session_id = _mutable_session_id(payload.session_id, identity.profile)
    try:
        with profile_scope(identity.profile):
            return save_session_draft(
                session_id,
                text=payload.text,
                files=payload.files,
            )
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc


@router.post("/session/toolsets")
def session_toolsets(
    payload: SessionToolsetsUpdate,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_mutations import set_session_toolsets

    session_id = _mutable_session_id(payload.session_id, identity.profile)
    try:
        with profile_scope(identity.profile):
            return set_session_toolsets(session_id, payload.toolsets)
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc


@router.post("/session/duplicate")
def duplicate_session(
    payload: SessionMutation,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_mutations import duplicate_session as duplicate

    session_id = _mutable_session_id(payload.session_id, identity.profile)
    try:
        with profile_scope(identity.profile):
            session = duplicate(session_id)
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc
    return {"session": session.compact() | {"messages": session.messages}}


@router.post("/session/truncate")
def truncate_session(
    payload: SessionTruncate,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_mutations import truncate_session as truncate

    session_id = _mutable_session_id(payload.session_id, identity.profile)
    try:
        keep_count = int(payload.keep_count)
    except (TypeError, ValueError) as exc:
        raise CoreApiError(400, "keep_count must be an integer") from exc
    if keep_count < 0:
        raise CoreApiError(400, "keep_count must be non-negative")
    try:
        with profile_scope(identity.profile):
            session = truncate(session_id, keep_count)
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc
    return {"ok": True, "session": session.compact() | {"messages": session.messages}}


@router.post("/session/branch")
def branch_session(
    payload: SessionBranch,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_mutations import branch_session as branch

    session_id = _mutable_session_id(payload.session_id, identity.profile)
    keep_count = payload.keep_count
    if keep_count is not None:
        try:
            keep_count = int(keep_count)
        except (TypeError, ValueError) as exc:
            raise CoreApiError(400, "keep_count must be an integer") from exc
        if keep_count < 0:
            raise CoreApiError(400, "keep_count must be non-negative")
    title = str(payload.title or "").strip()[:80] or None
    try:
        with profile_scope(identity.profile):
            created = branch(session_id, keep_count=keep_count, title=title)
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc
    except PermissionError as exc:
        raise CoreApiError(403, str(exc)) from exc
    return {
        "session_id": created.session_id,
        "title": created.title,
        "parent_session_id": session_id,
    }


@router.post("/session/rename")
def rename_session(
    payload: SessionRename,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_mutations import rename_session as rename

    session_id = _mutable_session_id(payload.session_id, identity.profile)
    try:
        with profile_scope(identity.profile):
            session = rename(session_id, payload.title)
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc
    except PermissionError as exc:
        raise CoreApiError(403, str(exc)) from exc
    return {"session": session.compact()}


@router.post("/session/clear")
def clear_session(
    payload: SessionMutation,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_mutations import clear_session as clear

    session_id = _mutable_session_id(payload.session_id, identity.profile)
    try:
        with profile_scope(identity.profile):
            session = clear(session_id)
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc
    return {"ok": True, "session": session.compact()}


@router.post("/session/worktree/remove")
def remove_worktree(
    payload: SessionWorktreeRemove,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_mutations import remove_session_worktree

    session_id = _mutable_session_id(payload.session_id, identity.profile)
    try:
        with profile_scope(identity.profile):
            return remove_session_worktree(session_id, force=payload.force)
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except Exception as exc:
        raise CoreApiError(500, "Failed to remove session worktree") from exc


@router.post("/sessions/cleanup")
def cleanup_empty_untitled_sessions(
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_mutations import cleanup_sessions

    with profile_scope(identity.profile):
        return cleanup_sessions(zero_only=False)


@router.post("/sessions/cleanup_zero_message")
def cleanup_zero_message_sessions(
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_mutations import cleanup_sessions

    with profile_scope(identity.profile):
        return cleanup_sessions(zero_only=True)


@router.post("/session/pin")
def pin_session(
    payload: SessionPin,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_mutations import set_session_pinned

    session_id = _mutable_session_id(payload.session_id, identity.profile)
    try:
        with profile_scope(identity.profile):
            session = set_session_pinned(session_id, payload.pinned)
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    return {"ok": True, "session": session.compact()}


@router.post("/session/archive")
def archive_session(
    payload: SessionArchive,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_mutations import set_session_archived, worktree_retained_payload

    session_id = _mutable_session_id(payload.session_id, identity.profile)
    try:
        with profile_scope(identity.profile):
            session = set_session_archived(session_id, payload.archived)
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc
    except PermissionError as exc:
        raise CoreApiError(400, str(exc)) from exc
    return {"ok": True, "session": session.compact(), **worktree_retained_payload(session)}


@router.post("/session/move")
def move_session(
    payload: SessionMove,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_mutations import move_session_to_project

    session_id = _mutable_session_id(payload.session_id, identity.profile)
    try:
        with profile_scope(identity.profile):
            session = move_session_to_project(session_id, payload.project_id)
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc
    except LookupError as exc:
        raise CoreApiError(404, str(exc)) from exc
    except PermissionError as exc:
        raise CoreApiError(403, str(exc)) from exc
    except TimeoutError as exc:
        raise CoreApiError(503, str(exc)) from exc
    return {"ok": True, "session": session.compact()}


@router.post("/session/conversation-rounds")
def conversation_rounds(
    payload: SessionConversationRounds,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.models import CONVERSATION_ROUND_THRESHOLD, count_conversation_rounds

    session_id = str(payload.session_id or "").strip()
    since = payload.since
    if since is not None:
        try:
            since = float(since)
        except (TypeError, ValueError) as exc:
            raise CoreApiError(400, "since must be a unix timestamp (number)") from exc
    with profile_scope(identity.profile):
        rounds = count_conversation_rounds(session_id, since=since)
    return {
        "ok": True,
        "rounds": rounds,
        "threshold": CONVERSATION_ROUND_THRESHOLD,
        "should_show": rounds >= CONVERSATION_ROUND_THRESHOLD,
    }


@router.post("/session/title/regenerate")
def regenerate_title(
    payload: SessionTitleRegenerate,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_mutations import SessionMutationError, regenerate_session_title

    session_id = _mutable_session_id(payload.session_id, identity.profile)
    try:
        with profile_scope(identity.profile):
            session, reason, raw_preview = regenerate_session_title(
                session_id,
                prefer_latest=payload.prefer_latest,
            )
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc
    except PermissionError as exc:
        raise CoreApiError(403, "Read-only imported sessions cannot regenerate titles") from exc
    except SessionMutationError as exc:
        raise CoreApiError(exc.status_code, str(exc)) from exc
    return {
        "session": session.compact(),
        "title": session.title,
        "status": reason,
        "raw_preview": raw_preview,
    }


@router.post("/session/delete")
def delete_session(
    payload: SessionMutation,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_mutations import SessionMutationError, delete_session as delete

    try:
        with profile_scope(identity.profile):
            return delete(payload.session_id)
    except SessionMutationError as exc:
        raise CoreApiError(exc.status_code, str(exc)) from exc


@router.post("/session/import")
def import_session(
    payload: SessionImportPayload,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_mutations import SessionMutationError, import_session_export

    data = payload.model_dump(exclude_unset=True)
    if data.get("workspace") is None:
        data.pop("workspace", None)
    if data.get("model") is None:
        data.pop("model", None)
    if data.get("tool_calls") is None:
        data.pop("tool_calls", None)
    try:
        with profile_scope(identity.profile):
            session = import_session_export(data)
    except SessionMutationError as exc:
        raise CoreApiError(exc.status_code, str(exc)) from exc
    return {"ok": True, "session": session.compact() | {"messages": session.messages}}


@router.post("/session/import_cli")
async def import_cli_session(
    payload: SessionCliImport,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.cli_session_import import CliImportError, import_cli_session_record

    raw_all_profiles = payload.all_profiles
    all_profiles = (
        raw_all_profiles.strip().lower() in {"1", "true", "yes", "on"}
        if isinstance(raw_all_profiles, str)
        else bool(raw_all_profiles)
    )
    try:
        return await asyncio.to_thread(
            _profile_compress,
            identity.profile,
            import_cli_session_record,
            payload.session_id,
            requested_profile=payload.profile,
            all_profiles=all_profiles,
            active_profile=identity.profile or "default",
        )
    except CliImportError as exc:
        raise CoreApiError(exc.status_code, str(exc)) from exc


@router.post("/session/handoff-summary")
async def handoff_summary(
    payload: SessionHandoffSummary,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.handoff_summary import HandoffSummaryError, generate_handoff_summary

    since = payload.since
    if since is not None:
        try:
            since = float(since)
        except (TypeError, ValueError) as exc:
            raise CoreApiError(400, "since must be a unix timestamp (number)") from exc
    try:
        return await asyncio.to_thread(
            _profile_compress,
            identity.profile,
            generate_handoff_summary,
            payload.session_id,
            since=since,
        )
    except HandoffSummaryError as exc:
        raise CoreApiError(exc.status_code, str(exc)) from exc


@router.post("/session/anchor-scene")
async def anchor_scene(
    payload: SessionAnchorScene,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.anchor_scenes import AnchorSceneError, persist_anchor_scene

    if payload.scene is None:
        raise CoreApiError(400, "Missing required field(s): scene")
    try:
        return await asyncio.to_thread(
            _profile_compress,
            identity.profile,
            persist_anchor_scene,
            payload.session_id,
            payload.scene,
            active_profile=identity.profile or "default",
            message_index=payload.message_index,
            message_offset=payload.message_offset,
            message_window_index=payload.message_window_index,
            message_reference=payload.message_ref,
            stream_id=payload.stream_id,
        )
    except AnchorSceneError as exc:
        raise CoreApiError(exc.status_code, str(exc)) from exc


@router.post("/session/update")
def update_session(
    payload: SessionUpdate,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.session_mutations import SessionMutationError, update_session_execution_lane

    session_id = _mutable_session_id(payload.session_id, identity.profile)
    fields = payload.model_fields_set
    try:
        with profile_scope(identity.profile):
            session = update_session_execution_lane(
                session_id,
                workspace=payload.workspace,
                model=payload.model,
                model_provider=payload.model_provider,
                model_was_set="model" in fields,
                provider_was_set="model_provider" in fields,
            )
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc
    except SessionMutationError as exc:
        raise CoreApiError(exc.status_code, str(exc)) from exc
    return {"session": session.compact() | {"messages": session.messages}}


@router.post("/session/compression-recovery/start")
def compression_recovery_start(
    payload: SessionMutation,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.helpers import redact_session_data
    from api.session_mutations import SessionMutationError, start_compression_recovery

    try:
        with profile_scope(identity.profile):
            session, created, action = start_compression_recovery(payload.session_id)
    except SessionMutationError as exc:
        raise CoreApiError(exc.status_code, str(exc)) from exc
    return {
        "ok": True,
        "session": redact_session_data(session.compact() | {"messages": session.messages}),
        "source_session_id": payload.session_id,
        "recommended_recovery_action": action,
        "message": (
            "Started a focused continuation. Describe the next narrow task to continue."
            if created
            else "Opened the existing focused continuation for this exhausted session."
        ),
    }


def _compression_error(exc):
    from api.manual_compression import CompressionError

    if isinstance(exc, CompressionError):
        return CoreApiError(exc.status_code, str(exc))
    return CoreApiError(500, "Compression failed")


def _profile_compress(profile, operation, *args, **kwargs):
    with profile_scope(profile):
        return operation(*args, **kwargs)


@router.post("/session/compress")
async def compress_session(
    payload: SessionCompression,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.manual_compression import CompressionError, compress_session as compress

    try:
        return await asyncio.to_thread(
            _profile_compress,
            identity.profile,
            compress,
            payload.session_id,
            focus_topic=payload.focus_topic or payload.topic,
        )
    except CompressionError as exc:
        raise _compression_error(exc) from exc


@router.post("/session/compress/start")
async def start_session_compression(
    payload: SessionCompression,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.manual_compression import CompressionError, start_compression

    try:
        return await asyncio.to_thread(
            _profile_compress,
            identity.profile,
            start_compression,
            payload.session_id,
            focus_topic=payload.focus_topic or payload.topic,
        )
    except CompressionError as exc:
        raise _compression_error(exc) from exc


@router.get("/session/compress/status")
async def session_compression_status(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
):
    from api.manual_compression import CompressionError, compression_status

    try:
        return await asyncio.to_thread(
            _profile_compress,
            identity.profile,
            compression_status,
            session_id,
        )
    except CompressionError as exc:
        raise _compression_error(exc) from exc
