"""Canonical session-detail projection shared by FastAPI and non-HTTP callers."""

from __future__ import annotations

import json

from api.session_access import is_messaging_session_record, lookup_cli_session_metadata
from api.session_display import message_window_for_display
from api.session_lineage_display import (
    merged_webui_lineage_messages_for_display,
    webui_sidecar_lineage_messages_for_display,
)


_TOOL_CONTENT_LIMIT = 4096
_TOOL_CONTENT_NOTICE = (
    "\n\n[Tool output truncated in paginated session response; "
    "load the full transcript to inspect the complete result.]"
)


def metadata_only_message_summary(session_id: str, profile: str | None = None) -> dict:
    """Return a profile-scoped transcript summary without loading full rows."""

    from api.models import Session, get_state_db_session_summary

    sidecar = Session.load_metadata_only(session_id)
    sidecar_count = 0
    sidecar_last = 0.0
    if sidecar:
        try:
            sidecar_count = int(getattr(sidecar, "_metadata_message_count", 0) or 0)
        except (TypeError, ValueError):
            sidecar_count = 0
        if sidecar_count <= 0:
            try:
                sidecar_count = int(sidecar.compact().get("message_count") or 0)
            except (TypeError, ValueError):
                sidecar_count = 0
        try:
            sidecar_last = float(getattr(sidecar, "updated_at", 0) or 0)
        except (TypeError, ValueError):
            sidecar_last = 0.0
        if getattr(sidecar, "truncation_watermark", None) is not None:
            return {"message_count": sidecar_count, "last_message_at": sidecar_last}
    state = get_state_db_session_summary(session_id, profile=profile)
    try:
        state_count = int(state.get("message_count") or 0)
    except (TypeError, ValueError):
        state_count = 0
    try:
        state_last = float(state.get("last_message_at") or 0)
    except (TypeError, ValueError):
        state_last = 0.0
    if state_count > sidecar_count and state_last > sidecar_last:
        return {"message_count": state_count, "last_message_at": state_last}
    return {"message_count": sidecar_count, "last_message_at": sidecar_last}


_metadata_only_message_summary = metadata_only_message_summary


def session_requires_cli_metadata_lookup(session) -> bool:
    if not session:
        return False
    field = session.get if isinstance(session, dict) else lambda key, default=None: getattr(session, key, default)
    if is_messaging_session_record(session) or bool(field("is_cli_session")) or bool(field("read_only")):
        return True
    source = str(field("session_source") or "").strip().lower()
    if source in {"messaging", "external_agent", "external-agent"}:
        return True
    return any(
        str(field(key) or "").strip()
        for key in ("source_tag", "raw_source", "source", "source_label", "platform")
    )


def merged_session_messages_for_display(session, external_messages=None) -> list:
    from api.models import _session_message_merge_key, merge_session_messages_append_only

    external = list(external_messages or [])
    sidecar = webui_sidecar_lineage_messages_for_display(session)
    if not external:
        return sidecar
    if not sidecar or sidecar == external:
        return external if len(external) >= len(sidecar) else sidecar
    if len(sidecar) >= len(external):
        return merge_session_messages_append_only(
            sidecar,
            external,
            truncation_watermark=getattr(session, "truncation_watermark", None),
            truncation_boundary=getattr(session, "truncation_boundary", None),
        )
    result, seen = [], set()
    for message in sorted(
        external + sidecar,
        key=lambda item: (
            float((item or {}).get("timestamp") or 0),
            str((item or {}).get("role") or ""),
            str((item or {}).get("content") or ""),
        ),
    ):
        key = _session_message_merge_key(message)
        if key not in seen:
            seen.add(key)
            result.append(message)
    return result


def merge_cli_sidebar_metadata(payload: dict, metadata: dict) -> dict:
    if not metadata:
        return payload
    from api.agent_sessions import is_cli_session_row

    merged = dict(payload)
    merged["is_cli_session"] = is_cli_session_row(metadata)
    for key in (
        "source_tag", "raw_source", "session_source", "source_label", "user_id",
        "chat_id", "chat_type", "thread_id", "session_key", "platform",
        "parent_session_id", "end_reason", "actual_message_count",
        "_lineage_root_id", "_lineage_tip_id", "_compression_segment_count",
    ):
        value = metadata.get(key)
        if value not in (None, ""):
            merged[key] = value
    for key in ("created_at", "updated_at", "last_message_at"):
        if metadata.get(key) is not None:
            merged[key] = metadata[key]
    return merged


def _bounded_messages(messages) -> list:
    result = []
    for message in messages or []:
        if not isinstance(message, dict) or str(message.get("role") or "").lower() != "tool":
            result.append(message)
            continue
        content = message.get("content")
        if content in (None, ""):
            result.append(message)
            continue
        text = content if isinstance(content, str) else json.dumps(content, ensure_ascii=False, default=str)
        if len(text) <= _TOOL_CONTENT_LIMIT:
            result.append(message)
            continue
        clipped = dict(message)
        preview = text[:_TOOL_CONTENT_LIMIT] + _TOOL_CONTENT_NOTICE
        if isinstance(content, str):
            clipped["content"] = preview
        elif isinstance(content, list):
            clipped["content"] = [{"type": "text", "text": preview}]
        elif isinstance(content, dict):
            clipped["content"] = {"_truncated": True, "preview": preview}
        else:
            clipped["content"] = preview
        clipped["_content_truncated"] = True
        clipped["_content_original_chars"] = len(text)
        result.append(clipped)
    return result


def tool_calls_for_message_window(tool_calls, start: int, count: int) -> list:
    result = []
    for raw in tool_calls or []:
        if not isinstance(raw, dict):
            continue
        index = raw.get("assistant_msg_idx")
        if isinstance(index, bool) or not isinstance(index, int):
            continue
        if start <= index < start + count:
            item = dict(raw)
            item["assistant_msg_idx"] = index - start
            result.append(item)
    return result


def project_session_detail(
    session,
    *,
    load_messages: bool = True,
    message_limit: int | None = None,
    message_before: int | None = None,
    resolve_model: bool = True,
) -> dict:
    """Build the stable `/api/session` payload without transport dependencies."""
    from api.models import get_cli_session_messages, get_state_db_session_messages, merge_session_messages_append_only
    from api.model_context import session_context_projection
    from api.model_resolution import (
        _resolve_effective_session_model_for_display,
        _resolve_effective_session_model_provider_for_display,
    )

    metadata = lookup_cli_session_metadata(session.session_id) if session_requires_cli_metadata_lookup(session) else {}
    messaging = is_messaging_session_record(session) or is_messaging_session_record(metadata)
    if messaging:
        all_messages = merged_session_messages_for_display(
            session,
            get_cli_session_messages(session.session_id, profile=getattr(session, "profile", None)),
        )
    elif load_messages:
        sidecar = webui_sidecar_lineage_messages_for_display(session)
        state_rows = get_state_db_session_messages(
            session.session_id,
            profile=getattr(session, "profile", None),
        )
        all_messages = merge_session_messages_append_only(
            sidecar,
            state_rows,
            truncation_watermark=getattr(session, "truncation_watermark", None),
            truncation_boundary=getattr(session, "truncation_boundary", None),
        )
        if message_limit is None:
            all_messages = merged_webui_lineage_messages_for_display(session, all_messages)
    else:
        all_messages = list(getattr(session, "messages", []) or [])
    if load_messages:
        messages, offset = message_window_for_display(
            all_messages,
            msg_limit=message_limit,
            msg_before=message_before,
        )
        if message_limit is not None:
            messages = _bounded_messages(messages)
    else:
        messages, offset = [], 0

    try:
        payload = session.compact(include_runtime=True)
    except TypeError:
        payload = session.compact()
    effective_model = _resolve_effective_session_model_for_display(session) if resolve_model else None
    effective_provider = _resolve_effective_session_model_provider_for_display(session) if resolve_model else None
    context_length, threshold = session_context_projection(
        session,
        effective_model,
        effective_provider,
        resolve_model=resolve_model,
    )
    payload.update(
        messages=messages,
        message_count=len(all_messages),
        messages_total=len(all_messages),
        messages_start=offset,
        messages_has_more=offset > 0,
        tool_calls=(
            tool_calls_for_message_window(getattr(session, "tool_calls", []), offset, len(messages))
            if message_limit is not None
            else list(getattr(session, "tool_calls", []) or [])
        ) if load_messages else [],
        active_stream_id=getattr(session, "active_stream_id", None),
        pending_user_message=getattr(session, "pending_user_message", None),
        pending_attachments=list(getattr(session, "pending_attachments", []) or []) if load_messages else [],
        pending_started_at=getattr(session, "pending_started_at", None),
        context_length=context_length,
        threshold_tokens=threshold,
        _messages_offset=offset,
        _messages_truncated=bool(load_messages and message_limit is not None and offset > 0),
    )
    if not load_messages:
        summary = metadata_only_message_summary(
            session.session_id,
            profile=getattr(session, "profile", None),
        )
        payload.update(summary)
        payload["messages_total"] = summary["message_count"]
    if effective_model:
        payload["model"] = effective_model
    if effective_provider:
        payload["model_provider"] = effective_provider
    if metadata and messaging:
        payload = merge_cli_sidebar_metadata(payload, metadata)
        payload["message_count"] = len(all_messages)
    if all_messages:
        try:
            last_message_at = max(float((item or {}).get("timestamp") or 0) for item in all_messages)
        except (TypeError, ValueError):
            last_message_at = 0
        if last_message_at:
            payload["last_message_at"] = max(float(payload.get("last_message_at") or 0), last_message_at)
    return payload


_is_messaging_session_record = is_messaging_session_record
_merge_cli_sidebar_metadata = merge_cli_sidebar_metadata
_merged_session_messages_for_display = merged_session_messages_for_display
_messages_for_limited_payload = _bounded_messages
_session_requires_cli_metadata_lookup = session_requires_cli_metadata_lookup
_tool_calls_for_message_window = tool_calls_for_message_window


__all__ = [
    "merge_cli_sidebar_metadata",
    "metadata_only_message_summary",
    "merged_session_messages_for_display",
    "project_session_detail",
    "session_requires_cli_metadata_lookup",
    "tool_calls_for_message_window",
]
