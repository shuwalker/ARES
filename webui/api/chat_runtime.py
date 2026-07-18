"""Framework-neutral chat-run creation for HTTP and background callers.

This module owns the short transaction that prepares a session, registers its
established ARES stream channel, and starts the selected framework worker. It
does not own model generation: connected runtimes publish through
``api.config.StreamChannel`` and the run journal.
"""

from __future__ import annotations

import logging
import threading
import time
import uuid
from typing import Any

from api.config import (
    ACTIVE_RUNS,
    ACTIVE_RUNS_LOCK,
    PENDING_BG_TASK_COMPLETIONS,
    PENDING_GOAL_CONTINUATION,
    STREAMS,
    STREAMS_LOCK,
    STREAM_GOAL_RELATED,
    _get_session_agent_lock,
    create_stream_channel,
    get_config,
    get_effective_default_model,
    get_webui_session_save_mode,
    register_stream_owner,
    unregister_stream_owner,
)
from api.models import get_session, title_from
from api.session_events import publish_session_list_changed
from api.workspace import get_last_workspace, resolve_trusted_workspace, set_last_workspace


logger = logging.getLogger(__name__)


def normalize_chat_attachments(raw_attachments) -> list[dict[str, Any]]:
    """Normalize legacy filenames and structured browser upload results."""

    if not isinstance(raw_attachments, list):
        return []
    normalized: list[dict[str, Any]] = []
    for item in raw_attachments:
        if isinstance(item, dict):
            name = str(item.get("name") or item.get("filename") or "").strip()
            path = str(item.get("path") or "").strip()
            attachment: dict[str, Any] = {
                "name": name or path,
                "path": path,
                "mime": str(item.get("mime") or "").strip(),
            }
            if isinstance(item.get("size"), int):
                attachment["size"] = item["size"]
            if isinstance(item.get("is_image"), bool):
                attachment["is_image"] = item["is_image"]
            normalized.append(attachment)
        else:
            value = str(item).strip()
            if value:
                normalized.append({"name": value, "path": "", "mime": ""})
    return normalized


_normalize_chat_attachments = normalize_chat_attachments


def resolve_chat_workspace_with_recovery(session: Any, requested_workspace) -> str:
    """Repair a stale implicit workspace while preserving explicit errors."""
    explicit = requested_workspace not in (None, "")
    candidate = requested_workspace if explicit else getattr(session, "workspace", None)
    try:
        return str(resolve_trusted_workspace(candidate))
    except ValueError:
        if explicit:
            raise
    fallback = str(resolve_trusted_workspace(get_last_workspace()))
    session.workspace = fallback
    try:
        session.save()
    except Exception:
        pass
    return fallback


_resolve_chat_workspace_with_recovery = resolve_chat_workspace_with_recovery


def _active_run_for_session(session_id: str) -> str | None:
    """Return a currently registered worker for ``session_id``."""
    with ACTIVE_RUNS_LOCK:
        for key, value in list((ACTIVE_RUNS or {}).items()):
            record = value if isinstance(value, dict) else {}
            if str(record.get("session_id") or "") == session_id:
                return str(record.get("stream_id") or key or "") or None
    return None


def _stream_is_active(stream_id: str | None) -> bool:
    if not stream_id:
        return False
    with STREAMS_LOCK:
        if stream_id in STREAMS:
            return True
    with ACTIVE_RUNS_LOCK:
        return stream_id in (ACTIVE_RUNS or {})


def _clear_stale_pending_locked(session: Any, stream_id: str) -> bool:
    """Clear a dead pending run while the canonical session lock is held."""
    if _stream_is_active(stream_id):
        return False
    pending_started_at = getattr(session, "pending_started_at", None)
    try:
        pending_age = time.time() - float(pending_started_at) if pending_started_at else None
    except (TypeError, ValueError):
        pending_age = None
    try:
        from api.models import _REPAIR_STALE_PENDING_GRACE_SECONDS

        grace = float(_REPAIR_STALE_PENDING_GRACE_SECONDS)
    except Exception:
        grace = 30.0
    if (
        getattr(session, "pending_user_message", None)
        and pending_age is not None
        and pending_age < grace
    ):
        return False

    try:
        from api.streaming import _materialize_pending_user_turn_before_error

        _materialize_pending_user_turn_before_error(session)
    except Exception:
        logger.exception("Could not materialize stale pending turn for %s", session.session_id)
        return False

    session.active_stream_id = None
    session.pending_user_message = None
    session.pending_attachments = []
    session.pending_started_at = None
    session.pending_user_source = None
    session.save(touch_updated_at=False)
    unregister_stream_owner(stream_id)
    return True


def _checkpoint_eager_user_message(
    session: Any,
    message: str,
    attachments: list[dict[str, Any]],
    started_at: float,
    source: str,
) -> None:
    existing = list(getattr(session, "messages", None) or [])
    if existing:
        latest = existing[-1]
        if isinstance(latest, dict) and latest.get("role") == "user":
            if " ".join(str(latest.get("content") or "").split()) == " ".join(message.split()):
                return
    row: dict[str, Any] = {
        "role": "user",
        "content": message,
        "timestamp": int(started_at),
    }
    if source != "webui":
        row["_source"] = source
    if attachments:
        row["attachments"] = list(attachments)
    session.messages.append(row)
    if getattr(session, "truncation_watermark", None):
        session.truncation_watermark = row["timestamp"] or time.time()


def checkpoint_user_message_for_eager_session_save(
    session: Any,
    msg: str,
    attachments,
    started_at: float | None,
    source: str = "webui",
) -> None:
    """Persist an eager user checkpoint without depending on HTTP transport."""
    if not msg:
        return
    existing = list(getattr(session, "messages", None) or [])
    if existing:
        latest = existing[-1]
        if isinstance(latest, dict) and latest.get("role") == "user":
            latest_text = " ".join(str(latest.get("content") or "").split())
            if latest_text == " ".join(str(msg).split()):
                return
    row: dict[str, Any] = {"role": "user", "content": msg}
    if source and source != "webui":
        row["_source"] = source
    if isinstance(started_at, (int, float)) and started_at > 0:
        row["timestamp"] = int(started_at)
    if attachments:
        row["attachments"] = list(attachments)
    session.messages.append(row)
    if getattr(session, "truncation_watermark", None):
        session.truncation_watermark = row.get("timestamp") or time.time()


_checkpoint_user_message_for_eager_session_save = checkpoint_user_message_for_eager_session_save


def prepare_chat_start_session_for_stream(
    session: Any,
    *,
    msg: str,
    attachments,
    workspace: str,
    model: str,
    model_provider,
    stream_id: str,
    started_at: float | None = None,
    source: str = "webui",
):
    """Persist pending chat state using the configured eager/deferred mode."""
    del started_at
    _prepare_session_locked(
        session,
        stream_id=stream_id,
        message=msg,
        attachments=list(attachments or []),
        workspace=workspace,
        model=model,
        provider=model_provider,
        source=source,
    )
    return session


_prepare_chat_start_session_for_stream = prepare_chat_start_session_for_stream


def _prepare_session_locked(
    session: Any,
    *,
    stream_id: str,
    message: str,
    attachments: list[dict[str, Any]],
    workspace: str,
    model: str,
    provider: str | None,
    source: str,
) -> tuple[bool, float]:
    was_hidden = (
        getattr(session, "title", "Untitled") == "Untitled"
        and not getattr(session, "messages", None)
        and not getattr(session, "active_stream_id", None)
        and not getattr(session, "pending_user_message", None)
    )
    started_at = time.time()
    session.workspace = workspace
    session.model = model
    session.model_provider = provider
    session.active_stream_id = stream_id
    session.post_compression_context_tokens_estimate = None
    session.pending_user_message = message
    session.pending_attachments = attachments
    session.pending_started_at = started_at
    session.pending_user_source = source
    if str(getattr(session, "title", "") or "").strip() in {"", "Untitled", "New Chat"}:
        session.title = title_from([{"role": "user", "content": message}], "Untitled")
    if get_webui_session_save_mode() == "eager":
        _checkpoint_eager_user_message(session, message, attachments, started_at, source)
    session.save()
    return was_hidden, started_at


def _backend_for_session(session: Any):
    from api.backend_selector import get_session_backend
    from api.backends.router import get_router

    selected = get_session_backend(session, get_config())
    router = get_router()
    backend = router.backends.get(selected)
    if backend:
        return backend
    raise ValueError(f"Unknown runtime connection: {selected}")


def start_session_turn(
    session_id: str,
    message: str,
    *,
    source: str = "process_wakeup",
    backend: Any | None = None,
    workspace: str | None = None,
    model: str | None = None,
    model_provider: str | None = None,
    attachments: list[dict[str, Any]] | None = None,
    _skip_wakeup_policy: bool = False,
) -> dict[str, Any]:
    """Start a runtime worker without importing the legacy HTTP dispatcher.

    FastAPI adapters execute this synchronous transaction with
    ``asyncio.to_thread`` so filesystem work and runtime checks do not block the
    event loop. Background wakeups can call it directly from their worker.
    """
    clean_message = str(message or "").strip()
    if not clean_message:
        return {"error": "message is required", "_status": 400}
    if source == "process_wakeup" and not _skip_wakeup_policy:
        from api.process_wakeup import start_session_turn as start_process_wakeup

        return start_process_wakeup(session_id, clean_message, source=source)
    try:
        session = get_session(str(session_id or "").strip(), metadata_only=False)
    except KeyError:
        return {"error": "Session not found", "_status": 404}

    cfg = get_config()
    model_cfg = cfg.get("model") if isinstance(cfg, dict) else {}
    model_cfg = model_cfg if isinstance(model_cfg, dict) else {}
    requested_model = str(
        model
        or getattr(session, "model", None)
        or get_effective_default_model(cfg)
        or ""
    ).strip()
    requested_provider = str(
        model_provider
        or getattr(session, "model_provider", None)
        or model_cfg.get("provider")
        or ""
    ).strip() or None
    from api.model_resolution import resolve_chat_model_state

    effective_model, effective_provider = resolve_chat_model_state(
        session,
        requested_model or None,
        requested_provider,
        explicit_model_pick=bool(model),
        prefer_cached_catalog=source != "webui",
    )
    try:
        effective_workspace = resolve_chat_workspace_with_recovery(session, workspace)
    except ValueError as exc:
        return {"error": str(exc), "_status": 400}

    try:
        selected_backend = backend or _backend_for_session(session)
    except ValueError as exc:
        return {"error": str(exc), "_status": 400}

    session_lock = _get_session_agent_lock(session.session_id)
    with session_lock:
        try:
            session = get_session(session.session_id, metadata_only=False)
        except KeyError:
            return {"error": "Session not found", "_status": 404}
        current_stream_id = str(getattr(session, "active_stream_id", None) or "")
        if current_stream_id:
            if (
                _stream_is_active(current_stream_id)
                or not _clear_stale_pending_locked(session, current_stream_id)
            ):
                return {
                    "error": "session already has an active stream",
                    "active_stream_id": current_stream_id,
                    "_status": 409,
                }
        active_run = _active_run_for_session(session.session_id)
        if active_run:
            return {
                "error": "session already has an active stream",
                "active_stream_id": active_run,
                "_status": 409,
            }
        stream_id = uuid.uuid4().hex
        was_hidden, started_at = _prepare_session_locked(
            session,
            stream_id=stream_id,
            message=clean_message,
            attachments=list(attachments or []),
            workspace=effective_workspace,
            model=effective_model,
            provider=effective_provider,
            source=str(source or "webui").strip() or "webui",
        )

    if was_hidden:
        publish_session_list_changed(
            "session_new",
            profile=getattr(session, "profile", None),
            session_id=session.session_id,
        )

    journal_event: dict[str, Any] = {}
    try:
        from api.turn_journal import append_turn_journal_event

        journal_event = append_turn_journal_event(
            session.session_id,
            {
                "event": "submitted",
                "stream_id": stream_id,
                "role": "user",
                "content": clean_message,
                "attachments": list(attachments or []),
                "workspace": effective_workspace,
                "model": effective_model,
                "model_provider": effective_provider,
                "created_at": started_at,
            },
        )
    except Exception:
        logger.warning("Failed to append submitted turn journal event", exc_info=True)

    set_last_workspace(effective_workspace)
    channel = create_stream_channel()
    register_stream_owner(stream_id, session.session_id)
    with STREAMS_LOCK:
        STREAMS[stream_id] = channel

    goal_related = session.session_id in PENDING_GOAL_CONTINUATION
    PENDING_GOAL_CONTINUATION.discard(session.session_id)
    PENDING_BG_TASK_COMPLETIONS.discard(session.session_id)
    if goal_related:
        STREAM_GOAL_RELATED[stream_id] = True

    worker_target, _is_gateway, _is_jros = selected_backend.get_worker_target()
    worker = threading.Thread(
        target=worker_target,
        args=(
            session.session_id,
            clean_message,
            effective_model,
            effective_workspace,
            stream_id,
            list(attachments or []),
        ),
        kwargs={"model_provider": effective_provider, "goal_related": goal_related},
        name=f"ares-run-{stream_id[:8]}",
        daemon=True,
    )
    try:
        worker.start()
    except Exception as exc:
        with STREAMS_LOCK:
            STREAMS.pop(stream_id, None)
        unregister_stream_owner(stream_id)
        with session_lock:
            session.active_stream_id = None
            session.pending_user_message = None
            session.pending_attachments = []
            session.pending_started_at = None
            session.pending_user_source = None
            session.save(touch_updated_at=False)
        logger.exception("Could not start runtime worker for %s", session.session_id)
        return {"error": f"Could not start assistant runtime: {exc}", "_status": 500}

    response = {
        "stream_id": stream_id,
        "session_id": session.session_id,
        "pending_started_at": started_at,
        "turn_id": journal_event.get("turn_id"),
        "title": session.title,
        "effective_model": effective_model,
    }
    if effective_provider:
        response["effective_model_provider"] = effective_provider

    try:
        from api.background_process import get_session_channel

        activity_channel = get_session_channel(session.session_id)
        if activity_channel is not None:
            activity_channel.emit(
                "server_turn_started",
                {
                    "session_id": session.session_id,
                    "stream_id": stream_id,
                    "pending_started_at": started_at,
                    "source": source,
                },
            )
    except Exception:
        logger.debug("server_turn_started fan-out failed", exc_info=True)
    return response


__all__ = ["resolve_chat_workspace_with_recovery", "start_session_turn"]
