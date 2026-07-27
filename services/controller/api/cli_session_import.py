"""Transport-neutral import of CLI and external-runtime session records."""

from __future__ import annotations

from api.models import (
    Session,
    _profile_has_user_projects,
    ensure_cron_project,
    get_cli_session_messages,
    get_cli_sessions,
    get_last_workspace,
    import_cli_session,
    is_cron_session,
    title_from,
)
from api.profiles import _is_isolated_profile_mode, _profiles_match
from api.session_access import is_subagent_child_session_id
from api.session_events import publish_session_list_changed


class CliImportError(RuntimeError):
    def __init__(self, status_code: int, message: str):
        super().__init__(message)
        self.status_code = status_code


def _normalize_profile(value) -> str | None:
    profile = str(value or "").strip()
    if not profile:
        return None
    from api.profiles import _PROFILE_ID_RE

    if profile != "default" and not _PROFILE_ID_RE.fullmatch(profile):
        raise CliImportError(400, "invalid profile")
    return profile


def _lookup_metadata(session_id: str, *, profile: str | None, all_profiles: bool) -> dict:
    try:
        rows = get_cli_sessions(all_profiles=all_profiles)
    except Exception:
        return {}
    for row in rows:
        if row.get("session_id") != session_id:
            continue
        if profile and not _profiles_match(row.get("profile"), profile):
            continue
        return row
    return {}


def _normalize_message(message):
    if not isinstance(message, dict):
        return message
    result = dict(message)
    result.pop("timestamp", None)
    result.pop("_ts", None)
    return result


def messages_refresh_prefix_matches(existing: list, fresh: list) -> bool:
    return (
        isinstance(existing, list)
        and isinstance(fresh, list)
        and len(existing) <= len(fresh)
        and all(_normalize_message(message) == _normalize_message(fresh[index]) for index, message in enumerate(existing))
    )


def _has_tool_metadata(message) -> bool:
    return isinstance(message, dict) and (
        (message.get("role") == "assistant" and bool(message.get("tool_calls")))
        or (
            message.get("role") == "tool"
            and bool(message.get("tool_call_id") or message.get("tool_name") or message.get("name"))
        )
    )


def _strip_tool_metadata(message):
    normalized = _normalize_message(message)
    if not isinstance(normalized, dict):
        return normalized
    for key in ("tool_calls", "tool_call_id", "tool_name", "name"):
        normalized.pop(key, None)
    return normalized


def tool_metadata_enriches(existing: list, fresh: list) -> bool:
    return (
        isinstance(existing, list)
        and isinstance(fresh, list)
        and len(existing) == len(fresh)
        and not any(_has_tool_metadata(message) for message in existing)
        and any(_has_tool_metadata(message) for message in fresh)
        and all(_strip_tool_metadata(message) == _strip_tool_metadata(fresh[index]) for index, message in enumerate(existing))
    )


def _is_subagent(session_id: str, metadata: dict) -> bool:
    source = str(metadata.get("source_tag") or metadata.get("raw_source") or "").strip().lower()
    return source == "subagent" or is_subagent_child_session_id(session_id)


def _refresh_existing(existing, metadata: dict, fresh: list) -> bool:
    changed = False
    if fresh and len(fresh) > len(existing.messages) and messages_refresh_prefix_matches(existing.messages, fresh):
        existing.messages = fresh
        changed = True
    elif fresh and tool_metadata_enriches(existing.messages, fresh):
        existing.messages = fresh
        changed = True
    subagent = _is_subagent(
        str(getattr(existing, "session_id", None) or metadata.get("session_id") or ""),
        metadata,
    )
    updates = {
        "is_cli_session": not subagent,
        "source_tag": existing.source_tag or metadata.get("source_tag"),
        "raw_source": existing.raw_source or metadata.get("raw_source") or metadata.get("source_tag"),
        "session_source": existing.session_source or metadata.get("session_source"),
        "source_label": existing.source_label or metadata.get("source_label"),
        "parent_session_id": existing.parent_session_id or metadata.get("parent_session_id"),
    }
    if subagent:
        updates["read_only"] = True
    for field, value in updates.items():
        if getattr(existing, field, None) != value:
            setattr(existing, field, value)
            changed = True
    if changed:
        existing.save(touch_updated_at=False)
        publish_session_list_changed("session_import_cli", profile=getattr(existing, "profile", None))
    return subagent


def import_cli_session_record(
    session_id: str,
    *,
    requested_profile: str | None = None,
    all_profiles: bool = False,
    active_profile: str | None = None,
) -> dict:
    session_id = str(session_id or "").strip()
    if not session_id:
        raise CliImportError(400, "Missing required field(s): session_id")
    requested_profile = _normalize_profile(requested_profile)
    if all_profiles and _is_isolated_profile_mode():
        raise CliImportError(403, "all_profiles import is not allowed in isolated profile mode")
    if all_profiles and not requested_profile:
        raise CliImportError(400, "profile is required for all_profiles import")

    existing = Session.load(session_id)
    if existing:
        existing_profile = getattr(existing, "profile", None)
        if all_profiles:
            if requested_profile and not _profiles_match(existing_profile, requested_profile):
                raise CliImportError(404, "Session not found in CLI store")
        elif not _profiles_match(existing_profile, active_profile or "default"):
            raise CliImportError(404, "Session not found in CLI store")
        refresh_profile = requested_profile or existing_profile
        metadata = _lookup_metadata(session_id, profile=refresh_profile, all_profiles=all_profiles)
        fresh = get_cli_session_messages(
            session_id,
            profile=metadata.get("profile") or refresh_profile,
        )
        subagent = _refresh_existing(existing, metadata, fresh)
        return {
            "session": existing.compact()
            | {
                "messages": existing.messages,
                "is_cli_session": not subagent,
                "read_only": bool(getattr(existing, "read_only", False)),
            },
            "imported": False,
        }

    metadata = _lookup_metadata(
        session_id,
        profile=requested_profile,
        all_profiles=all_profiles,
    )
    profile = metadata.get("profile") or (requested_profile if all_profiles else None)
    messages = get_cli_session_messages(session_id, profile=profile)
    if not messages:
        raise CliImportError(404, "Session not found in CLI store")
    model = metadata.get("model", "unknown") if metadata else "unknown"
    title = metadata.get("title") or title_from(messages, "CLI Session")
    subagent = _is_subagent(session_id, metadata)
    read_only = bool(metadata.get("read_only")) or subagent
    if read_only:
        return {
            "session": {
                "session_id": session_id,
                "title": title,
                "workspace": str(get_last_workspace()),
                "model": model,
                "message_count": len(messages),
                "created_at": metadata.get("created_at"),
                "updated_at": metadata.get("updated_at"),
                "last_message_at": metadata.get("updated_at") or metadata.get("created_at"),
                "pinned": False,
                "archived": False,
                "project_id": None,
                "profile": profile,
                "is_cli_session": not subagent,
                "source_tag": metadata.get("source_tag"),
                "raw_source": metadata.get("raw_source") or metadata.get("source_tag"),
                "session_source": metadata.get("session_source"),
                "source_label": metadata.get("source_label"),
                "parent_session_id": metadata.get("parent_session_id"),
                "read_only": True,
                "messages": messages,
                "tool_calls": [],
            },
            "imported": False,
        }
    cron_project_id = (
        ensure_cron_project(create=_profile_has_user_projects())
        if is_cron_session(session_id, metadata.get("source_tag"))
        else None
    )
    session = import_cli_session(
        session_id,
        title,
        messages,
        model,
        profile=profile,
        created_at=metadata.get("created_at"),
        updated_at=metadata.get("updated_at"),
        parent_session_id=metadata.get("parent_session_id"),
    )
    session.project_id = cron_project_id or session.project_id
    session.is_cli_session = True
    for field in (
        "source_tag",
        "raw_source",
        "session_source",
        "source_label",
        "user_id",
        "chat_id",
        "chat_type",
        "thread_id",
        "session_key",
        "platform",
    ):
        value = metadata.get(field)
        if field == "raw_source":
            value = value or metadata.get("source_tag")
        setattr(session, field, value)
    session._cli_origin = session_id
    session.save(touch_updated_at=False)
    publish_session_list_changed("session_import_cli", profile=getattr(session, "profile", None))
    return {
        "session": session.compact() | {"messages": messages, "is_cli_session": True},
        "imported": True,
    }


def _handle_session_import_cli(_handler, body):
    """Compatibility-shaped domain entrypoint retained for focused unit tests."""
    return import_cli_session_record(
        str((body or {}).get("session_id") or ""),
        requested_profile=(body or {}).get("profile"),
        all_profiles=bool((body or {}).get("all_profiles")),
    )
