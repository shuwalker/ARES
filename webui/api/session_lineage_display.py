"""Display-only merging for WebUI continuation lineage."""

from __future__ import annotations

from api.models import (
    Session,
    _session_message_visible_key,
    is_safe_session_id,
    merge_session_messages_append_only,
)


def _key(message: dict) -> tuple:
    return (
        str(message.get("role") or ""),
        str(message.get("content") or ""),
        message.get("timestamp"),
    )


def merged_webui_lineage_messages_for_display(session, messages=None) -> list:
    primary = list(messages if messages is not None else (getattr(session, "messages", []) or []))
    parent_id = str(getattr(session, "parent_session_id", "") or "").strip()
    source = str(getattr(session, "session_source", "") or "").strip().lower()
    relationship = str(getattr(session, "relationship_type", "") or "").strip().lower()
    if not parent_id or source == "fork" or relationship == "child_session":
        return primary
    try:
        from api.models import get_session

        parent = get_session(parent_id, metadata_only=False)
    except Exception:
        return primary
    combined = list(getattr(parent, "messages", []) or []) + primary
    def ordering(message):
        if message.get("timestamp") is None:
            return (1, 0.0, "", "")
        return (
            0,
            float(message.get("timestamp") or 0),
            str(message.get("role") or ""),
            str(message.get("content") or ""),
        )

    combined.sort(key=ordering)
    result = []
    seen = {}
    for raw in combined:
        message = dict(raw)
        key = _key(message)
        if key in seen:
            seen[key].update({name: value for name, value in message.items() if value is not None})
            continue
        seen[key] = message
        result.append(message)
    return result


def _messages_start_with_visible_prefix(messages, prefix) -> bool:
    messages = list(messages or [])
    prefix = list(prefix or [])
    if not prefix:
        return True
    if len(messages) < len(prefix):
        return False
    try:
        return all(
            _session_message_visible_key(messages[index])
            == _session_message_visible_key(prefix_message)
            for index, prefix_message in enumerate(prefix)
        )
    except Exception:
        return False


def webui_sidecar_lineage_messages_for_display(session, *, max_hops: int = 20) -> list:
    """Stitch compression snapshot sidecars without joining ordinary forks."""
    segments = []
    current = session
    session_messages = list(getattr(session, "messages", []) or [])
    root_is_fork = str(getattr(session, "session_source", "") or "").strip().lower() == "fork"
    seen = {str(getattr(session, "session_id", "") or "")}
    for _ in range(max(0, int(max_hops))):
        parent_id = str(getattr(current, "parent_session_id", "") or "").strip()
        if not parent_id or parent_id in seen or not is_safe_session_id(parent_id):
            break
        parent = Session.load(parent_id)
        if not parent or not getattr(parent, "pre_compression_snapshot", False):
            break
        parent_source = str(getattr(parent, "session_source", "") or "").strip().lower()
        if root_is_fork and parent_source != "fork":
            break
        if not segments and _messages_start_with_visible_prefix(
            session_messages,
            getattr(parent, "messages", []) or [],
        ):
            return session_messages
        segments.append(parent)
        seen.add(parent_id)
        current = parent
    if not segments:
        return session_messages
    merged = []
    for segment in reversed(segments):
        merged = merge_session_messages_append_only(
            merged,
            getattr(segment, "messages", []) or [],
            truncation_watermark=getattr(segment, "truncation_watermark", None),
            truncation_boundary=getattr(segment, "truncation_boundary", None),
        )
    return merge_session_messages_append_only(
        merged,
        session_messages,
        truncation_watermark=None,
    )


_merged_webui_lineage_messages_for_display = merged_webui_lineage_messages_for_display
_webui_sidecar_lineage_messages_for_display = webui_sidecar_lineage_messages_for_display


__all__ = [
    "merged_webui_lineage_messages_for_display",
    "webui_sidecar_lineage_messages_for_display",
]
