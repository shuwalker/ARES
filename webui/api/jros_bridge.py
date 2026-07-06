"""Default-off JROS bridge for browser-originated ARES chat turns.

This is intentionally shaped like ``api.gateway_chat._run_gateway_chat_streaming``:
/api/chat/start still creates a normal local WebUI stream, /api/chat/stream still
receives WebUI SSE event names, and the final turn is persisted back into the
same WebUI session model.  The only swapped piece is execution: instead of
calling Hermes Gateway/OpenAI-compatible chat, this boots JROS and runs the turn
through JROS' native ``run_for_voice`` API.
"""
from __future__ import annotations

import contextlib
import logging
import os
import sys
import threading
import time
from pathlib import Path
from typing import Any

from api.config import (
    CANCEL_FLAGS,
    PENDING_GOAL_CONTINUATION,
    STREAM_GOAL_RELATED,
    STREAM_LAST_EVENT_ID,
    STREAM_LIVE_TOOL_CALLS,
    STREAM_PARTIAL_TEXT,
    STREAM_REASONING_TEXT,
    STREAMS,
    STREAMS_LOCK,
    _get_session_agent_lock,
    register_active_run,
    unregister_active_run,
    unregister_stream_owner,
    update_active_run,
)
from api.helpers import _redact_text, redact_session_data
from api.models import get_session, merge_session_messages_append_only
from api.run_journal import RunJournalWriter

logger = logging.getLogger(__name__)

_BOOT_LOCK = threading.RLock()
_BOOT: Any | None = None


def _jros_repo_root() -> Path:
    override = os.environ.get("ARES_JROS_DIR", "").strip()
    if override:
        return Path(override).expanduser().resolve()
    return (Path.home() / "GitHub" / "JROS").resolve()


def _jros_instance_name() -> str:
    return os.environ.get("ARES_JROS_INSTANCE", "jros-dev").strip() or "jros-dev"


def _ensure_jros_import_path() -> None:
    root = str(_jros_repo_root())
    if root not in sys.path:
        sys.path.insert(0, root)


def _boot_jros() -> Any:
    """Boot and cache the JROS TUI pipeline for WebUI-originated turns."""
    global _BOOT
    with _BOOT_LOCK:
        if _BOOT is not None:
            return _BOOT
        _ensure_jros_import_path()
        from jaeger_os.main import boot_for_tui

        with contextlib.redirect_stdout(sys.stderr):
            _BOOT = boot_for_tui(
                instance_name=_jros_instance_name(),
                with_memory=True,
                warmup=False,
                prewarm_model=False,
            )
        return _BOOT


def _stream_writeback_is_current(session: Any, stream_id: str) -> bool:
    return bool(stream_id and getattr(session, "active_stream_id", None) == stream_id)


def _clear_jros_pending_state(session: Any, stream_id: str) -> None:
    if not _stream_writeback_is_current(session, stream_id):
        return
    session.active_stream_id = None
    session.pending_user_message = None
    session.pending_attachments = None
    session.pending_started_at = None
    session.pending_user_source = None
    session.save()


def _assistant_text_from_jros_result(result: Any) -> tuple[str, str, list[str]]:
    payload = dict(result or {}) if isinstance(result, dict) else {}
    error = str(payload.get("error") or "").strip()
    text = str(payload.get("text") or payload.get("content") or payload.get("response") or "").strip()
    tool_activity = payload.get("tool_activity") or []
    if not isinstance(tool_activity, list):
        tool_activity = [str(tool_activity)]
    return text, error, [str(item) for item in tool_activity if str(item).strip()]


def _merge_and_save_jros_turn(
    *,
    session_id: str,
    stream_id: str,
    msg_text: str,
    assistant_text: str,
    workspace: str,
    model: str,
    attachments: list | None,
) -> Any:
    with _get_session_agent_lock(session_id):
        s = get_session(session_id)
        if not _stream_writeback_is_current(s, stream_id):
            return None
        now = time.time()
        assistant_ts = now + 0.000001
        user_msg = {"role": "user", "content": str(msg_text or ""), "timestamp": now}
        pending_source = getattr(s, "pending_user_source", None) or "webui"
        if pending_source != "webui":
            user_msg["_source"] = pending_source
        if attachments:
            user_msg["attachments"] = list(attachments)
        assistant_msg = {
            "role": "assistant",
            "content": assistant_text,
            "timestamp": assistant_ts,
            "backend": "jros",
            "model_provider": "jros",
        }
        saved_reasoning = STREAM_REASONING_TEXT.get(stream_id, "")
        if saved_reasoning:
            assistant_msg["reasoning"] = saved_reasoning
        previous_context = list(getattr(s, "context_messages", None) or getattr(s, "messages", None) or [])
        s.context_messages = previous_context + [user_msg, assistant_msg]
        try:
            from api.streaming import _is_context_compression_marker

            display_context = [
                msg
                for msg in previous_context
                if not _is_context_compression_marker(msg)
            ]
        except Exception:
            logger.debug("Failed to filter JROS display context markers", exc_info=True)
            display_context = previous_context
        display = merge_session_messages_append_only(
            list(getattr(s, "messages", None) or []),
            display_context,
        )
        try:
            from api.streaming import _merge_display_messages_after_agent_result

            s.messages = _merge_display_messages_after_agent_result(
                display,
                previous_context,
                s.context_messages,
                str(msg_text or ""),
                source=pending_source,
            )
            # Ensure the persisted assistant row carries the backend marker.
            for msg in reversed(s.messages):
                if isinstance(msg, dict) and msg.get("role") == "assistant" and msg.get("content") == assistant_text:
                    msg["backend"] = "jros"
                    msg["model_provider"] = "jros"
                    break
        except Exception:
            logger.debug("Failed to merge JROS display transcript", exc_info=True)
            if display:
                latest = display[-1]
                if isinstance(latest, dict) and latest.get("role") == "user":
                    latest_text = " ".join(str(latest.get("content") or "").split())
                    msg_norm = " ".join(str(msg_text or "").split())
                    if latest_text == msg_norm:
                        display = display[:-1]
            s.messages = display + [user_msg, assistant_msg]
        s.active_stream_id = None
        s.pending_user_message = None
        s.pending_attachments = None
        s.pending_started_at = None
        s.pending_user_source = None
        s.workspace = str(workspace)
        s.model = model or "jros"
        s.model_provider = "jros"
        s.save()
        return s


def _run_jros_goal_hook(*, session_id: str, stream_id: str, goal_related: bool, assistant_text: str, put_jros_event) -> None:
    try:
        from api.goals import evaluate_goal_after_turn, has_active_goal
        from api.profiles import get_hermes_home_for_profile

        s = get_session(session_id)
        profile_home = get_hermes_home_for_profile(str(getattr(s, "profile", None) or "default"))
        if goal_related and has_active_goal(session_id, profile_home=profile_home):
            put_jros_event("goal", {
                "session_id": session_id,
                "state": "evaluating",
                "message": "Evaluating goal progress…",
                "message_key": "goal_evaluating_progress",
            })
            decision = evaluate_goal_after_turn(
                session_id,
                assistant_text,
                user_initiated=True,
                profile_home=profile_home,
            ) or {}
            goal_message = str(decision.get("message") or "").strip()
            if goal_message:
                put_jros_event("goal", {
                    "session_id": session_id,
                    "state": "continuing" if decision.get("should_continue") else "idle",
                    "message": goal_message,
                    "message_key": decision.get("message_key") or ("goal_continuing" if goal_message else ""),
                    "message_args": decision.get("message_args") or [],
                    "decision": decision,
                })
            if decision.get("should_continue"):
                continuation_prompt = str(decision.get("continuation_prompt") or "").strip()
                if continuation_prompt:
                    PENDING_GOAL_CONTINUATION.add(session_id)
                    put_jros_event("goal_continue", {
                        "session_id": session_id,
                        "continuation_prompt": continuation_prompt,
                        "text": continuation_prompt,
                        "message": goal_message,
                        "message_key": decision.get("message_key") or "goal_continuing",
                        "message_args": decision.get("message_args") or [],
                        "decision": decision,
                    })
    except Exception as goal_exc:
        logger.debug("JROS goal continuation hook failed for session %s: %s", session_id, goal_exc)


def _run_jros_chat_streaming(
    session_id,
    msg_text,
    model,
    workspace,
    stream_id,
    attachments=None,
    *,
    model_provider=None,
    goal_related=False,
):
    """Bridge a WebUI chat turn through JROS using the Hermes worker contract."""
    q = STREAMS.get(stream_id)
    if q is None:
        unregister_stream_owner(stream_id)
        return
    register_active_run(
        stream_id,
        session_id=session_id,
        started_at=time.time(),
        phase="jros-starting",
        workspace=str(workspace),
        model=model or "jros",
        provider="jros",
        backend="jros",
    )
    try:
        run_journal = RunJournalWriter(session_id, stream_id)
    except Exception:
        run_journal = None
        logger.debug("Failed to initialize JROS run journal for stream %s", stream_id, exc_info=True)
    cancel_event = threading.Event()
    with STREAMS_LOCK:
        CANCEL_FLAGS[stream_id] = cancel_event
        STREAM_PARTIAL_TEXT[stream_id] = ""
        STREAM_REASONING_TEXT[stream_id] = ""
        STREAM_LIVE_TOOL_CALLS[stream_id] = []

    def put_jros_event(event, data):
        if cancel_event.is_set() and event not in ("cancel", "error", "apperror"):
            return
        event_id = None
        if run_journal is not None:
            try:
                journaled = run_journal.append_sse_event(event, data)
                event_id = (journaled or {}).get("event_id") if isinstance(journaled, dict) else None
                if event_id:
                    STREAM_LAST_EVENT_ID[stream_id] = event_id
            except Exception:
                logger.debug("Failed to append JROS event %s for stream %s", event, stream_id, exc_info=True)
        if event_id and hasattr(q, "note_last_event_id"):
            try:
                q.note_last_event_id(event_id)
            except Exception:
                logger.debug("Failed to note JROS event_id %s for stream %s", event_id, stream_id, exc_info=True)
        try:
            queue_item = (event, data, event_id) if event_id and hasattr(q, "subscribe_with_snapshot") else (event, data)
            q.put_nowait(queue_item)
        except Exception:
            logger.debug("Failed to put JROS event to queue", exc_info=True)

    s = None
    usage = {"input_tokens": 0, "output_tokens": 0, "estimated_cost": 0}
    try:
        s = get_session(session_id)
        put_jros_event("context_status", {
            "session_id": session_id,
            "prefill": {"status": "jros", "source": "jros", "label": "JROS", "message_count": 0},
        })
        update_active_run(stream_id, phase="jros-booting")
        boot = _boot_jros()
        if cancel_event.is_set():
            put_jros_event("cancel", {"message": "Cancelled by user"})
            return
        update_active_run(stream_id, phase="jros-request")
        from jaeger_os.main import run_for_voice

        with contextlib.redirect_stdout(sys.stderr):
            result = run_for_voice(boot.client, str(msg_text or ""), session_key=f"webui:{session_id}")
        if cancel_event.is_set():
            put_jros_event("cancel", {"message": "Cancelled by user"})
            return
        assistant_text, error, tool_activity = _assistant_text_from_jros_result(result)
        for activity in tool_activity:
            if stream_id in STREAM_LIVE_TOOL_CALLS:
                STREAM_LIVE_TOOL_CALLS[stream_id].append({"name": "jros", "args": {"activity": activity}, "done": True})
            put_jros_event("tool", {"event_type": "tool.progress", "name": "jros", "preview": activity, "is_error": False})
        if error:
            put_jros_event("apperror", {
                "label": "JROS request failed",
                "type": "jros_error",
                "message": _redact_text(error)[:500],
                "hint": "ARES reached the JROS backend. Check JROS provider config/quota if the model call failed.",
            })
            return
        if not assistant_text:
            put_jros_event("apperror", {
                "label": "JROS returned no response",
                "type": "jros_empty_response",
                "message": "JROS returned no assistant message for this turn.",
                "hint": f"Check the JROS {_jros_instance_name()} instance and model provider.",
            })
            return
        # JROS currently returns a complete turn, not token deltas. Emit one token
        # event so the browser keeps the exact Hermes WebUI stream contract.
        STREAM_PARTIAL_TEXT[stream_id] = assistant_text
        usage["output_tokens"] = max(1, len(assistant_text.split()))
        put_jros_event("token", {"text": assistant_text})
        saved_session = _merge_and_save_jros_turn(
            session_id=session_id,
            stream_id=stream_id,
            msg_text=str(msg_text or ""),
            assistant_text=assistant_text,
            workspace=str(workspace),
            model=model or "jros",
            attachments=attachments,
        )
        if saved_session is None:
            return
        _run_jros_goal_hook(
            session_id=session_id,
            stream_id=stream_id,
            goal_related=goal_related,
            assistant_text=assistant_text,
            put_jros_event=put_jros_event,
        )
        from api.streaming import _session_payload_with_full_messages

        payload = _session_payload_with_full_messages(saved_session, tool_calls=[])
        put_jros_event("done", {"session": redact_session_data(payload), "usage": usage})
        put_jros_event("stream_end", {"session_id": session_id})
    except Exception as exc:
        safe = _redact_text(str(exc))[:500]
        put_jros_event("apperror", {
            "label": "JROS request failed",
            "type": "jros_bridge_error",
            "message": safe or "JROS request failed.",
            "hint": f"Check the JROS {_jros_instance_name()} instance, import path, and provider health.",
        })
    finally:
        if s is not None:
            try:
                with _get_session_agent_lock(session_id):
                    _clear_jros_pending_state(get_session(session_id), stream_id)
            except Exception:
                logger.debug("Failed to clear JROS stream state", exc_info=True)
        with STREAMS_LOCK:
            CANCEL_FLAGS.pop(stream_id, None)
            STREAM_GOAL_RELATED.pop(stream_id, None)
            STREAM_PARTIAL_TEXT.pop(stream_id, None)
            STREAM_REASONING_TEXT.pop(stream_id, None)
            STREAM_LIVE_TOOL_CALLS.pop(stream_id, None)
            STREAM_LAST_EVENT_ID.pop(stream_id, None)
            STREAMS.pop(stream_id, None)
        unregister_active_run(stream_id)


# Backwards-compatible name used by early route patches/tests.
run_jros_streaming = _run_jros_chat_streaming
