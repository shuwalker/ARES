"""Small, transport-neutral session metadata mutations."""

from __future__ import annotations

from typing import Any
import copy
import json
import logging
import os
import shutil
import threading
import time
import uuid


MAX_DRAFT_TEXT = 50_000
MAX_DRAFT_FILES = 50
logger = logging.getLogger(__name__)
_COMPRESSION_RECOVERY_START_LOCK = threading.Lock()


class SessionMutationError(ValueError):
    def __init__(self, message: str, status_code: int = 400) -> None:
        super().__init__(message)
        self.status_code = status_code


def validate_session_toolsets_shape(toolsets):
    if toolsets is None:
        return None
    if not isinstance(toolsets, list) or not toolsets:
        raise ValueError("toolsets must be a non-empty list or null")
    if not all(isinstance(item, str) and item for item in toolsets):
        raise ValueError("each toolset must be a non-empty string")
    return toolsets


def get_session_draft(session_id: str) -> dict[str, Any]:
    from api.models import get_session

    session = get_session(session_id)
    return dict(getattr(session, "composer_draft", {}) or {})


def save_session_draft(
    session_id: str,
    *,
    text: Any = None,
    files: Any = None,
) -> dict[str, Any]:
    from api.config import _get_session_agent_lock
    from api.models import get_session

    if text is not None and not isinstance(text, str):
        text = ""
    if isinstance(text, str):
        text = text[:MAX_DRAFT_TEXT]
    if files is not None and not isinstance(files, list):
        files = []
    if isinstance(files, list):
        files = files[:MAX_DRAFT_FILES]
    session = get_session(session_id)
    with _get_session_agent_lock(session_id):
        current = dict(getattr(session, "composer_draft", {}) or {})
        updated = dict(current)
        if text is not None:
            updated["text"] = text
        if files is not None:
            updated["files"] = files
        if updated == current:
            return {"ok": True, "draft": current, "unchanged": True}
        session.composer_draft = updated
        session.save(touch_updated_at=False, skip_index=True)
    return {"ok": True, "draft": updated}


def set_session_toolsets(session_id: str, toolsets) -> dict[str, Any]:
    from api.config import _get_session_agent_lock
    from api.models import get_session

    normalized = validate_session_toolsets_shape(toolsets)
    session = get_session(session_id)
    with _get_session_agent_lock(session_id):
        session.enabled_toolsets = normalized
        session.save()
    return {"ok": True, "enabled_toolsets": session.enabled_toolsets}


def _sync_session_title_to_insights(session) -> None:
    try:
        from api.models import load_settings

        if not load_settings().get("sync_to_insights"):
            return
        from api.state_sync import sync_session_usage

        sync_session_usage(
            session_id=session.session_id,
            input_tokens=getattr(session, "input_tokens", 0) or 0,
            output_tokens=getattr(session, "output_tokens", 0) or 0,
            estimated_cost=getattr(session, "estimated_cost", 0.0),
            model=getattr(session, "model", ""),
            title=session.title,
            message_count=len(getattr(session, "messages", None) or []),
            profile=getattr(session, "profile", None),
            cache_read_tokens=getattr(session, "cache_read_tokens", 0) or 0,
            cache_write_tokens=getattr(session, "cache_write_tokens", 0) or 0,
        )
    except Exception:
        logger.debug("Failed to update session title in state.db", exc_info=True)


def rename_session(session_id: str, title: str):
    from api.config import _get_session_agent_lock
    from api.session_access import get_or_materialize_session
    from api.session_events import publish_session_list_changed
    from api.session_ops import apply_session_title_rename

    session = get_or_materialize_session(session_id)
    with _get_session_agent_lock(session_id):
        apply_session_title_rename(session, title)
        session.save()
    _sync_session_title_to_insights(session)
    publish_session_list_changed(
        "session_rename",
        profile=getattr(session, "profile", None),
        session_id=session_id,
    )
    return session


def persist_generated_session_title(session, title: str, *, event_reason: str):
    from api.config import LOCK, SESSIONS, _get_session_agent_lock
    from api.models import Session, _evict_sessions_over_cap
    from api.session_access import ensure_full_session_before_mutation
    from api.session_events import publish_session_list_changed
    from api.session_ops import mark_session_title_generated

    normalized = str(title or "").strip()[:80] or "Untitled"
    session_id = str(getattr(session, "session_id", "") or "")
    with _get_session_agent_lock(session_id):
        with LOCK:
            latest = SESSIONS.get(session_id)
            if latest is not None:
                SESSIONS.move_to_end(session_id)
        if latest is None:
            latest = Session.load(session_id)
            if latest is None:
                raise KeyError(session_id)
        latest = ensure_full_session_before_mutation(session_id, latest)
        if getattr(latest, "read_only", False):
            raise PermissionError(f"Session {session_id} is read-only")
        latest.title = normalized
        mark_session_title_generated(latest)
        latest.save(touch_updated_at=False)
        with LOCK:
            SESSIONS[session_id] = latest
            SESSIONS.move_to_end(session_id)
            _evict_sessions_over_cap()
    _sync_session_title_to_insights(latest)
    publish_session_list_changed(
        event_reason,
        profile=getattr(latest, "profile", None),
        session_id=session_id,
    )
    return latest


def regenerate_session_title(session_id: str, *, prefer_latest: bool = False):
    from api.session_access import get_or_materialize_session
    from api.streaming import generate_session_title_for_session

    session = get_or_materialize_session(session_id)
    title, reason, raw_preview = generate_session_title_for_session(
        session,
        prefer_latest=prefer_latest,
    )
    if not title:
        raise SessionMutationError(
            f"Could not generate a better title ({reason or 'empty'})",
            422,
        )
    updated = persist_generated_session_title(
        session,
        title,
        event_reason="session_title_regenerate",
    )
    return updated, reason, str(raw_preview or "")[:240]


def clear_session(session_id: str):
    """Persist a truncate-to-empty sentinel that blocks state.db replay."""

    from api.config import _evict_session_agent, _get_session_agent_lock
    from api.models import get_session
    from api.session_ops import apply_session_title_rename, truncate_session_at_keep

    session = get_session(session_id)
    with _get_session_agent_lock(session_id):
        had_messages = bool(session.messages or [])
        truncate_session_at_keep(session, 0)
        session.tool_calls = []

        parent_id = getattr(session, "parent_session_id", None)
        if parent_id:
            try:
                parent = get_session(parent_id, metadata_only=True)
                is_compression_parent = bool(
                    getattr(parent, "pre_compression_snapshot", False)
                )
            except Exception:
                is_compression_parent = False
            if is_compression_parent:
                session.parent_session_id = None
                session.compression_anchor_visible_idx = None
                session.compression_anchor_message_key = None

        session.active_stream_id = None
        session.pending_user_message = None
        session.pending_attachments = []
        session.pending_started_at = None
        session.pending_user_source = None
        session.clear_generation = uuid.uuid4().hex if had_messages else None
        apply_session_title_rename(session, "Untitled")
        session.save()

        persisted_clear = False
        try:
            persisted = json.loads(session.path.read_text(encoding="utf-8"))
            persisted_clear = (
                persisted.get("messages") == []
                and persisted.get("context_messages") == []
                and persisted.get("truncation_watermark") == 0.0
                and persisted.get("truncation_boundary") == 0.0
                and persisted.get("active_stream_id") is None
                and persisted.get("pending_user_message") is None
                and persisted.get("pending_attachments") == []
                and persisted.get("pending_started_at") is None
                and persisted.get("pending_user_source") is None
                and persisted.get("clear_generation") == session.clear_generation
            )
        except (OSError, json.JSONDecodeError, ValueError):
            logger.warning(
                "session clear could not verify persisted empty state for %s",
                session_id,
                exc_info=True,
            )
        if had_messages and persisted_clear:
            try:
                session.path.with_suffix(".json.bak").unlink(missing_ok=True)
            except OSError:
                logger.warning(
                    "session clear could not remove stale backup for %s",
                    session_id,
                    exc_info=True,
                )
    _evict_session_agent(session_id)
    return session


def remove_session_worktree(session_id: str, *, force: bool = False) -> dict[str, Any]:
    from api.models import get_session, is_safe_session_id
    from api.worktrees import remove_worktree_for_session

    if not is_safe_session_id(session_id):
        raise ValueError("Invalid session_id")
    session = get_session(session_id, metadata_only=True)
    return remove_worktree_for_session(session, force=force)


def cleanup_sessions(*, zero_only: bool = False) -> dict[str, Any]:
    """Remove empty sidecars and index-only ghosts under the index write lock."""

    from api.config import LOCK, SESSIONS, SESSION_DIR, SESSION_INDEX_FILE
    from api.models import Session

    cleaned = 0
    phase1_removed_ids: set[str] = set()
    for path in SESSION_DIR.glob("*.json"):
        if path.name.startswith("_"):
            continue
        try:
            session = Session.load(path.stem)
            should_delete = bool(
                session
                and len(session.messages) == 0
                and (zero_only or session.title == "Untitled")
            )
            if should_delete:
                with LOCK:
                    SESSIONS.pop(path.stem, None)
                path.unlink(missing_ok=True)
                cleaned += 1
                phase1_removed_ids.add(path.stem)
        except Exception:
            logger.debug("Failed to clean up session file %s", path)

    phase1_touched = bool(cleaned)
    phase2_rewrote_index = False
    if SESSION_INDEX_FILE.exists():
        try:
            from api.models import _INDEX_WRITE_LOCK, _safe_replace

            with _INDEX_WRITE_LOCK:
                index_rows = json.loads(SESSION_INDEX_FILE.read_bytes())
                if isinstance(index_rows, list):
                    live_ids = {
                        path.stem
                        for path in SESSION_DIR.glob("*.json")
                        if not path.name.startswith("_")
                    }
                    with LOCK:
                        in_memory_ids = set(SESSIONS)
                    survivors = []
                    for entry in index_rows:
                        session_id = entry.get("session_id")
                        if (
                            not session_id
                            or session_id in live_ids
                            or session_id in in_memory_ids
                        ):
                            survivors.append(entry)
                        elif session_id not in phase1_removed_ids:
                            cleaned += 1

                    if cleaned > 0 and len(survivors) < len(index_rows):
                        temp = SESSION_INDEX_FILE.with_suffix(
                            f".tmp.{os.getpid()}.{threading.current_thread().ident}"
                        )
                        payload = json.dumps(survivors, ensure_ascii=False, indent=2)
                        try:
                            with open(temp, "w", encoding="utf-8") as stream:
                                stream.write(payload)
                                stream.flush()
                                os.fsync(stream.fileno())
                            _safe_replace(temp, SESSION_INDEX_FILE)
                            phase2_rewrote_index = True
                        except Exception:
                            temp.unlink(missing_ok=True)
                            raise
        except Exception:
            logger.debug("Failed to clean up index-only session entries", exc_info=True)

    if phase1_touched and not phase2_rewrote_index and SESSION_INDEX_FILE.exists():
        SESSION_INDEX_FILE.unlink(missing_ok=True)
    return {"ok": True, "cleaned": cleaned}


def _session_field(session, field: str, default=None):
    return session.get(field, default) if isinstance(session, dict) else getattr(session, field, default)


def session_counts_toward_pin_quota(session) -> bool:
    from api.models import _hide_from_default_sidebar

    if not _session_field(session, "pinned", False) or _session_field(session, "archived", False):
        return False
    if isinstance(session, dict):
        row = session
    elif hasattr(session, "compact"):
        row = session.compact()
    else:
        row = {
            "pre_compression_snapshot": _session_field(session, "pre_compression_snapshot", False),
            "source_tag": _session_field(session, "source_tag", None),
            "default_hidden": _session_field(session, "default_hidden", False),
        }
    return not _hide_from_default_sidebar(row)


def session_row_lineage_root_id(session, sessions_by_id) -> str:
    session_id = str(_session_field(session, "session_id", "") or "")
    explicit = _session_field(session, "_lineage_root_id", None)
    if explicit:
        return str(explicit)
    if _session_field(session, "session_source", None) == "fork":
        return session_id
    current = session_id
    seen = {session_id} if session_id else set()
    parent = _session_field(session, "parent_session_id", None)
    while parent:
        parent = str(parent)
        if parent in seen:
            break
        current = parent
        seen.add(parent)
        parent_row = sessions_by_id.get(parent)
        if not parent_row:
            break
        parent = _session_field(parent_row, "parent_session_id", None)
    return current or session_id


def visible_pinned_lineage_ids(session_rows) -> set[str]:
    sessions_by_id = {
        str(_session_field(row, "session_id", "") or ""): row
        for row in session_rows
        if _session_field(row, "session_id", None)
    }
    return {
        root
        for row in session_rows
        if session_counts_toward_pin_quota(row)
        and (root := session_row_lineage_root_id(row, sessions_by_id))
    }


def set_session_pinned(session_id: str, pinned: bool = True):
    """Update pin state while enforcing visible-lineage quota atomically."""

    from api.config import LOCK, SESSIONS, _get_session_agent_lock, load_settings
    from api.models import all_sessions, get_session
    from api.session_access import ensure_full_session_before_mutation
    from api.session_events import publish_session_list_changed

    session = ensure_full_session_before_mutation(session_id, get_session(session_id))
    if pinned and not getattr(session, "pinned", False):
        persisted = [row for row in all_sessions() if session_counts_toward_pin_quota(row)]
        with LOCK:
            candidates = list(persisted)
            candidates.extend(
                row.compact()
                for row in SESSIONS.values()
                if session_counts_toward_pin_quota(row)
            )
            target = session.compact()
            candidates.append(target)
            roots = visible_pinned_lineage_ids(candidates)
            target_root = session_row_lineage_root_id(
                target,
                {
                    str(_session_field(row, "session_id", "") or ""): row
                    for row in candidates
                    if _session_field(row, "session_id", None)
                },
            )
            roots.discard(target_root)
            limit = int(load_settings().get("pinned_sessions_limit", 3) or 3)
            if len(roots) >= limit:
                raise ValueError(
                    f"Up to {limit} sessions can be pinned. Unpin one before pinning another."
                )
            session.pinned = True
        with _get_session_agent_lock(session_id):
            session.save()
    else:
        with _get_session_agent_lock(session_id):
            session.pinned = bool(pinned)
            session.save()
    publish_session_list_changed(
        "session_pin",
        profile=getattr(session, "profile", None),
        session_id=session_id,
    )
    return session


def worktree_retained_payload(session) -> dict[str, Any]:
    path = getattr(session, "worktree_path", None) if session else None
    if not path:
        return {}
    payload = {"worktree_retained": True, "worktree_path": path}
    if getattr(session, "worktree_branch", None):
        payload["worktree_branch"] = session.worktree_branch
    if getattr(session, "worktree_repo_root", None):
        payload["worktree_repo_root"] = session.worktree_repo_root
    return payload


def set_session_archived(session_id: str, archived: bool = True):
    from api.agent_sessions import is_cli_session_row
    from api.config import _get_session_agent_lock
    from api.models import (
        Session,
        get_cli_session_messages,
        get_last_workspace,
        get_session,
        import_cli_session,
        title_from,
    )
    from api.session_access import (
        apply_source_metadata,
        ensure_full_session_before_mutation,
        is_messaging_session_record,
        lookup_cli_session_metadata,
    )
    from api.session_events import publish_session_list_changed

    try:
        session = ensure_full_session_before_mutation(session_id, get_session(session_id))
    except KeyError:
        metadata = lookup_cli_session_metadata(session_id)
        if not metadata:
            raise
        if metadata.get("read_only"):
            raise PermissionError("Read-only imported sessions cannot be archived from WebUI") from None
        source = str(metadata.get("source_tag") or metadata.get("raw_source") or "").strip().lower()
        if source == "subagent":
            raise PermissionError("Subagent sessions cannot be archived from WebUI") from None
        messages = get_cli_session_messages(session_id)
        title = metadata.get("title") or title_from(messages, "CLI Session")
        if is_messaging_session_record(metadata):
            session = Session(
                session_id=session_id,
                title=title,
                workspace=get_last_workspace(),
                messages=[],
                model=metadata.get("model") or "unknown",
                created_at=metadata.get("created_at"),
                updated_at=metadata.get("updated_at"),
            )
            session.is_cli_session = is_cli_session_row(metadata)
            apply_source_metadata(session, metadata)
            session.save(touch_updated_at=False)
        else:
            if not messages:
                raise KeyError(session_id) from None
            session = import_cli_session(
                session_id,
                title,
                messages,
                metadata.get("model") or "unknown",
                profile=metadata.get("profile"),
                created_at=metadata.get("created_at"),
                updated_at=metadata.get("updated_at"),
            )
            apply_source_metadata(session, metadata)
    with _get_session_agent_lock(session_id):
        session.archived = bool(archived)
        session.save(touch_updated_at=False)
    publish_session_list_changed(
        "session_archive",
        profile=getattr(session, "profile", None),
        session_id=session_id,
    )
    return session


def move_session_to_project(session_id: str, project_id: str | None):
    from api.config import _get_session_agent_lock
    from api.models import load_projects
    from api.profiles import _profiles_match, get_active_profile_name
    from api.session_access import get_or_materialize_session
    from api.session_events import publish_session_list_changed

    session = get_or_materialize_session(session_id)
    target_id = str(project_id or "").strip() or None
    if target_id:
        profile = getattr(session, "profile", None) or get_active_profile_name()
        target = next(
            (row for row in load_projects() if row.get("project_id") == target_id),
            None,
        )
        if not target or not _profiles_match(target.get("profile"), profile):
            raise LookupError("Project not found")
    lock = _get_session_agent_lock(session_id)
    if not lock.acquire(timeout=5):
        raise TimeoutError("Session is busy (streaming). Please try again in a moment.")
    try:
        session.project_id = target_id
        session.save()
    finally:
        lock.release()
    publish_session_list_changed(
        "session_move",
        profile=getattr(session, "profile", None),
        session_id=session_id,
    )
    return session


def delete_session(session_id: str) -> dict[str, Any]:
    """Delete every WebUI-owned durable artifact for one mutable session."""

    from api.config import (
        LOCK,
        SESSIONS,
        SESSION_AGENT_LOCKS,
        SESSION_AGENT_LOCKS_LOCK,
        SESSION_DIR,
        _evict_session_agent,
    )
    from api.models import (
        Session,
        _record_webui_deleted_session_tombstone,
        delete_cli_session,
        get_session,
        is_safe_session_id,
        prune_session_from_index,
    )
    from api.session_access import (
        is_messaging_session_record,
        lookup_cli_session_metadata,
        session_is_subagent_view_only,
    )
    from api.session_events import publish_session_list_changed

    session_id = str(session_id or "").strip()
    if not is_safe_session_id(session_id):
        raise SessionMutationError("Invalid session_id")
    metadata = lookup_cli_session_metadata(session_id)
    if metadata.get("read_only"):
        raise SessionMutationError("Read-only imported sessions cannot be deleted from WebUI")
    if session_is_subagent_view_only(session_id):
        raise SessionMutationError(
            "Subagent sessions are view-only and cannot be deleted from WebUI"
        )
    try:
        loaded = Session.load(session_id)
    except Exception:
        loaded = None
    is_messaging = is_messaging_session_record(loaded) or is_messaging_session_record(metadata)
    retained = worktree_retained_payload(loaded)
    try:
        event_profile = getattr(get_session(session_id, metadata_only=True), "profile", None)
    except Exception:
        event_profile = None

    with LOCK:
        SESSIONS.pop(session_id, None)
    _evict_session_agent(session_id)
    try:
        path = (SESSION_DIR / f"{session_id}.json").resolve()
        path.relative_to(SESSION_DIR.resolve())
    except Exception as exc:
        raise SessionMutationError("Invalid session_id") from exc

    try:
        path.unlink(missing_ok=True)
    except Exception:
        logger.debug("Failed to unlink session file %s", path)
    sidecar_deleted = not path.exists()
    try:
        path.with_suffix(".json.bak").unlink(missing_ok=True)
    except Exception:
        logger.debug("Failed to unlink session backup %s", path, exc_info=True)
    try:
        prune_session_from_index(session_id)
    except Exception:
        logger.debug("Failed to prune session index for %s", session_id, exc_info=True)
    if sidecar_deleted and not is_messaging:
        try:
            _record_webui_deleted_session_tombstone(session_id)
        except Exception:
            logger.debug("Failed to record deletion tombstone for %s", session_id, exc_info=True)
    try:
        from api.upload import _session_attachment_dir

        shutil.rmtree(_session_attachment_dir(session_id), ignore_errors=True)
    except Exception:
        logger.debug("Failed to remove session attachments for %s", session_id, exc_info=True)
    try:
        from api.turn_journal import delete_turn_journal

        delete_turn_journal(session_id)
    except Exception:
        logger.debug("Failed to remove turn journal for %s", session_id, exc_info=True)
    try:
        from api.run_journal import delete_run_journal

        delete_run_journal(session_id)
    except Exception:
        logger.debug("Failed to remove run journal for %s", session_id, exc_info=True)
    with SESSION_AGENT_LOCKS_LOCK:
        SESSION_AGENT_LOCKS.pop(session_id, None)
    try:
        from api.background_process import forget_bg_task_completion_dedup

        forget_bg_task_completion_dedup(session_id)
    except Exception:
        logger.debug("Failed to forget completion dedup for %s", session_id, exc_info=True)
    try:
        from api.terminal import close_terminal

        close_terminal(session_id)
    except Exception:
        logger.debug("Failed to close terminal for %s", session_id, exc_info=True)
    if not is_messaging:
        try:
            delete_cli_session(session_id)
        except Exception:
            logger.debug("Failed to delete state.db session %s", session_id, exc_info=True)
    publish_session_list_changed("session_delete", profile=event_profile)
    return {"ok": True, **retained}


def import_session_export(payload: dict[str, Any]):
    """Create a new Local Profile session from an exported JSON transcript."""

    from api.config import DEFAULT_MODEL, DEFAULT_WORKSPACE, LOCK, SESSIONS
    from api.models import Session, _evict_sessions_over_cap
    from api.profiles import get_active_profile_name
    from api.session_events import publish_session_list_changed
    from api.workspace import resolve_trusted_workspace

    messages = payload.get("messages")
    if not isinstance(messages, list):
        raise SessionMutationError('JSON must contain a "messages" array')
    try:
        workspace = str(
            resolve_trusted_workspace(payload.get("workspace", str(DEFAULT_WORKSPACE)))
        )
    except (TypeError, ValueError) as exc:
        raise SessionMutationError(str(exc)) from exc
    session = Session(
        title=payload.get("title", "Imported session"),
        workspace=workspace,
        model=payload.get("model", DEFAULT_MODEL),
        messages=messages,
        tool_calls=payload.get("tool_calls", []),
        profile=get_active_profile_name(),
    )
    session.pinned = payload.get("pinned", False)
    with LOCK:
        SESSIONS[session.session_id] = session
        SESSIONS.move_to_end(session.session_id)
        _evict_sessions_over_cap()
    session.save()
    publish_session_list_changed(
        "session_import",
        profile=getattr(session, "profile", None),
        session_id=session.session_id,
    )
    return session


def update_session_execution_lane(
    session_id: str,
    *,
    workspace: str | None = None,
    model: str | None = None,
    model_provider: str | None = None,
    model_was_set: bool = False,
    provider_was_set: bool = False,
):
    """Update workspace/model routing without coupling to an HTTP transport."""

    from api.config import (
        _evict_session_agent,
        _get_session_agent_lock,
        _is_known_model_provider,
        _resolve_provider_alias,
        canonical_model_provider_lane,
    )
    from api.session_access import get_or_materialize_session
    from api.terminal import close_terminal
    from api.workspace import resolve_trusted_workspace, set_last_workspace

    try:
        session = get_or_materialize_session(session_id)
    except PermissionError as exc:
        raise SessionMutationError(
            "Read-only imported sessions cannot be updated from WebUI",
            403,
        ) from exc
    old_workspace = str(getattr(session, "workspace", "") or "")
    old_model = str(getattr(session, "model", "") or "")
    old_provider = str(getattr(session, "model_provider", "") or "")
    try:
        next_workspace = str(
            resolve_trusted_workspace(workspace if workspace is not None else session.workspace)
        )
    except ValueError as exc:
        raise SessionMutationError(str(exc)) from exc
    with _get_session_agent_lock(session_id):
        session.workspace = next_workspace
        if model_was_set or provider_was_set:
            requested_model = model if model_was_set else getattr(session, "model", None)
            requested_provider = (
                model_provider if provider_was_set else getattr(session, "model_provider", None)
            )
            # Older clients send ``provider/model`` in the model field without
            # the separate model_provider lane. Normalize a known first-party
            # prefix deterministically instead of letting the process-global
            # active provider decide whether the prefix is stripped. Preserve
            # namespaced IDs for routing proxies/local endpoints, where the
            # slash is part of the model identifier (for example OpenRouter or
            # Hugging Face-style local model IDs).
            raw_model = str(requested_model or "").strip()
            inherited_provider = str(requested_provider or "").strip().lower()
            namespace_preserving_provider = (
                inherited_provider in {"openrouter", "custom", "nous", "opencode-zen", "opencode-go", "nvidia"}
                or inherited_provider.startswith("custom:")
            )
            if (
                model_was_set
                and not provider_was_set
                and "/" in raw_model
                and "://" not in raw_model
                and not namespace_preserving_provider
            ):
                provider_prefix, bare_model = raw_model.split("/", 1)
                canonical_prefix = str(_resolve_provider_alias(provider_prefix) or "").strip().lower()
                if bare_model and _is_known_model_provider(canonical_prefix):
                    requested_model = bare_model
                    requested_provider = canonical_prefix
            try:
                resolved_model, resolved_provider = canonical_model_provider_lane(
                    requested_model or "",
                    requested_provider,
                )
            except Exception as exc:
                raise SessionMutationError(str(exc)) from exc
            if resolved_model:
                session.model = resolved_model
            session.model_provider = resolved_provider
            if (
                old_model != str(getattr(session, "model", "") or "")
                or old_provider != str(getattr(session, "model_provider", "") or "")
            ):
                # Runtime hydration resolves the current provider's exact window.
                # Clear stale snapshots now so no threshold from the prior lane is reused.
                session.context_length = 0
                session.threshold_tokens = 0
                session.last_prompt_tokens = 0
                _evict_session_agent(session_id)
        session.save()
    if old_workspace != next_workspace:
        try:
            close_terminal(session_id)
        except Exception:
            logger.debug("Failed to close workspace terminal after workspace update")
    set_last_workspace(next_workspace)
    return session


def start_compression_recovery(session_id: str) -> tuple[Any, bool, str]:
    """Create or reuse the focused continuation for an exhausted session."""

    from api.compression_recovery import (
        COMPRESSION_RECOVERY_ACTION_START_FOCUSED,
        compression_recovery_payload_for_session,
    )
    from api.config import LOCK, SESSIONS
    from api.models import Session, _evict_sessions_over_cap, find_compression_recovery_session, get_session
    from api.profiles import _profiles_match, get_active_profile_name
    from api.session_access import session_is_subagent_view_only
    from api.session_events import publish_session_list_changed
    from api.workspace import get_last_workspace

    session_id = str(session_id or "").strip()
    if not session_id:
        raise SessionMutationError("session_id is required")
    if session_is_subagent_view_only(session_id):
        raise SessionMutationError(
            "Subagent sessions are view-only and cannot start compression recovery from WebUI"
        )
    try:
        source = get_session(session_id)
    except KeyError as exc:
        raise SessionMutationError("Session not found", 404) from exc
    source_profile = getattr(source, "profile", None)
    if not _profiles_match(source_profile, get_active_profile_name()):
        raise SessionMutationError("Session not found", 404)
    recovery = compression_recovery_payload_for_session(source)
    if not recovery:
        raise SessionMutationError(
            "Session does not have a compression recovery action.",
            409,
        )
    action = str(recovery.get("recommended_action") or "")
    if action != COMPRESSION_RECOVERY_ACTION_START_FOCUSED:
        raise SessionMutationError("Unsupported compression recovery action.", 409)

    created = False
    with _COMPRESSION_RECOVERY_START_LOCK:
        copied_session = find_compression_recovery_session(
            session_id,
            action,
            source_profile=source_profile,
        )
        if copied_session is None:
            title = str(getattr(source, "title", None) or "Untitled").strip() or "Untitled"
            if not title.endswith(" (focused continuation)"):
                title = f"{title} (focused continuation)"
            copied_session = Session(
                session_id=uuid.uuid4().hex[:12],
                title=title,
                workspace=getattr(source, "workspace", get_last_workspace()),
                model=getattr(source, "model", None),
                model_provider=getattr(source, "model_provider", None),
                messages=[],
                tool_calls=[],
                pinned=False,
                archived=False,
                project_id=getattr(source, "project_id", None),
                profile=source_profile,
                session_source="fork",
                personality=getattr(source, "personality", None),
                enabled_toolsets=copy.deepcopy(getattr(source, "enabled_toolsets", None)),
                context_length=getattr(source, "context_length", None),
                threshold_tokens=getattr(source, "threshold_tokens", None),
                gateway_routing=copy.deepcopy(getattr(source, "gateway_routing", None)),
                gateway_routing_history=copy.deepcopy(
                    getattr(source, "gateway_routing_history", None) or []
                ),
                parent_session_id=getattr(source, "session_id", session_id),
                worktree_path=getattr(source, "worktree_path", None),
                worktree_branch=getattr(source, "worktree_branch", None),
                worktree_repo_root=getattr(source, "worktree_repo_root", None),
                worktree_created_at=getattr(source, "worktree_created_at", None),
                compression_recovery_source_session_id=session_id,
                compression_recovery_action=action,
            )
            copied_session.context_messages = []
            copied_session.composer_draft = {"text": "", "files": []}
            try:
                copied_session.save()
            except Exception as exc:
                logger.exception(
                    "Failed to persist compression recovery session for %s",
                    session_id,
                )
                raise SessionMutationError(
                    f"Failed to start compression recovery: {exc}",
                    500,
                ) from exc
            with LOCK:
                SESSIONS[copied_session.session_id] = copied_session
                SESSIONS.move_to_end(copied_session.session_id)
                _evict_sessions_over_cap()
            created = True
    if created:
        publish_session_list_changed(
            "session_compression_recovery",
            profile=getattr(copied_session, "profile", None),
            session_id=getattr(copied_session, "session_id", None),
        )
    return copied_session, created, action


_session_counts_toward_pin_quota = session_counts_toward_pin_quota
_session_row_lineage_root_id = session_row_lineage_root_id
_visible_pinned_lineage_ids = visible_pinned_lineage_ids


def duplicate_session(session_id: str):
    from api.config import LOCK, SESSIONS
    from api.models import Session, _evict_sessions_over_cap

    original = Session.load(session_id)
    if original is None:
        raise KeyError(session_id)
    now = time.time()
    duplicate = Session(
        session_id=uuid.uuid4().hex[:12],
        title=(original.title or "Untitled") + " (copy)",
        workspace=original.workspace,
        model=original.model,
        model_provider=original.model_provider,
        messages=copy.deepcopy(original.messages),
        tool_calls=copy.deepcopy(original.tool_calls),
        pinned=False,
        archived=False,
        project_id=original.project_id,
        profile=original.profile,
        input_tokens=original.input_tokens,
        output_tokens=original.output_tokens,
        estimated_cost=original.estimated_cost,
        cache_read_tokens=getattr(original, "cache_read_tokens", 0),
        cache_write_tokens=getattr(original, "cache_write_tokens", 0),
        personality=original.personality,
        enabled_toolsets=getattr(original, "enabled_toolsets", None),
        context_length=getattr(original, "context_length", None),
        threshold_tokens=getattr(original, "threshold_tokens", None),
        truncation_watermark=getattr(original, "truncation_watermark", None),
        truncation_boundary=getattr(original, "truncation_boundary", None),
        context_messages=copy.deepcopy(getattr(original, "context_messages", None) or []),
        gateway_routing=copy.deepcopy(getattr(original, "gateway_routing", None)),
        gateway_routing_history=copy.deepcopy(getattr(original, "gateway_routing_history", None) or []),
        llm_title_generated=getattr(original, "llm_title_generated", False),
        manual_title=getattr(original, "manual_title", False),
        composer_draft=copy.deepcopy(getattr(original, "composer_draft", None) or {}),
        context_engine=getattr(original, "context_engine", None),
        context_engine_state=copy.deepcopy(getattr(original, "context_engine_state", None) or {}),
        created_at=now,
        updated_at=now,
    )
    with LOCK:
        SESSIONS[duplicate.session_id] = duplicate
        SESSIONS.move_to_end(duplicate.session_id)
        _evict_sessions_over_cap()
    duplicate.save()
    from api.session_events import publish_session_list_changed

    publish_session_list_changed(
        "session_duplicate",
        profile=getattr(duplicate, "profile", None),
        session_id=duplicate.session_id,
    )
    return duplicate


def truncate_session(session_id: str, keep_count: int):
    from api.config import _evict_session_agent, _get_session_agent_lock
    from api.models import get_session
    from api.session_ops import truncate_session_at_keep

    session = get_session(session_id)
    with _get_session_agent_lock(session_id):
        truncate_session_at_keep(session, keep_count)
        session.save()
    _evict_session_agent(session_id)
    return session


def branch_session(
    session_id: str,
    *,
    keep_count: int | None = None,
    title: str | None = None,
):
    from api.config import LOCK, SESSIONS
    from api.models import Session, _evict_sessions_over_cap, get_session
    from api.session_events import publish_session_list_changed
    from api.session_ops import truncate_context_for_display_keep

    source = get_session(session_id)
    if getattr(source, "read_only", False):
        raise PermissionError("Read-only imported sessions cannot be branched from WebUI")
    source_messages = list(source.messages or [])
    fork_keep = keep_count if keep_count is not None else len(source_messages)
    messages = copy.deepcopy(source_messages[:fork_keep])
    context = truncate_context_for_display_keep(
        getattr(source, "context_messages", None),
        source_messages,
        fork_keep,
    )
    branch = Session(
        workspace=source.workspace,
        model=source.model,
        model_provider=getattr(source, "model_provider", None),
        profile=getattr(source, "profile", None),
        title=title or f"{source.title or 'Untitled'} (fork)",
        messages=messages,
        project_id=getattr(source, "project_id", None),
        personality=getattr(source, "personality", None),
        enabled_toolsets=copy.deepcopy(getattr(source, "enabled_toolsets", None)),
        context_length=getattr(source, "context_length", None),
        threshold_tokens=getattr(source, "threshold_tokens", None),
        context_messages=copy.deepcopy(context),
        gateway_routing=copy.deepcopy(getattr(source, "gateway_routing", None)),
        context_engine=getattr(source, "context_engine", None),
        context_engine_state=copy.deepcopy(getattr(source, "context_engine_state", None) or {}),
        parent_session_id=source.session_id,
        session_source="fork",
    )
    with LOCK:
        SESSIONS[branch.session_id] = branch
        SESSIONS.move_to_end(branch.session_id)
        _evict_sessions_over_cap()
    if messages:
        branch.save()
        publish_session_list_changed(
            "session_branch",
            profile=getattr(branch, "profile", None),
            session_id=branch.session_id,
        )
    return branch


_validate_session_toolsets_shape = validate_session_toolsets_shape
