"""Default-off JROS gateway bridge for browser-originated ARES chat turns.

This is the JROS twin of ``api.gateway_chat`` (the Hermes Gateway bridge)
and is deliberately shaped like it: /api/chat/start still creates a normal
local WebUI stream, /api/chat/stream still receives WebUI SSE event names,
and the final turn is persisted back into the same WebUI session model.
The only swapped piece is execution, which resolves in this order:

1. **Gateway** — POST the turn to a JROS gateway server (``jaeger gateway``
   — jaeger_os/interfaces/http_gateway.py in the JROS repo, or the
   standalone ``webui/scripts/jros_gateway.py``) and relay its SSE reply.
   Works with a JROS on the same machine or on another one entirely:

       # where JROS is installed
       jaeger gateway --host 0.0.0.0 --port 8643
       # where ARES runs
       export ARES_JROS_GATEWAY_URL=http://<jros-host>:8643

2. **In-process fallback** — when no gateway is reachable but
   ``ARES_JROS_DIR`` points at a local JROS checkout, ARES boots JROS
   inside itself and runs the turn directly, so the local flip-the-toggle
   case needs no extra program at all. The two failure modes that sank the
   old in-process-only bridge surface as actionable errors instead of
   crashes: an already-running JROS (its exclusive instance lock) says
   close it or run ``jaeger gateway``, and a missing instance says run
   ``jaeger setup`` — the interactive wizard is never launched inside the
   web server.
"""
from __future__ import annotations

import contextlib
import json
import logging
import os
import sys
import threading
import time
import urllib.error
import urllib.request
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

_JROS_GATEWAY_URL_ENV = "ARES_JROS_GATEWAY_URL"
_JROS_GATEWAY_KEY_ENV = "ARES_JROS_GATEWAY_KEY"
DEFAULT_JROS_GATEWAY_URL = "http://127.0.0.1:8643"

_START_GATEWAY_HINT = (
    "Start the JROS gateway where JROS is installed (`jaeger gateway`, add "
    "`--host 0.0.0.0` for another machine) and point ARES_JROS_GATEWAY_URL "
    "at it."
)


def jros_gateway_base_url(config_data=None, environ: dict[str, str] | None = None) -> str:
    """Resolve the JROS gateway base URL: env override, then config, then
    the localhost default (same precedence as the Hermes gateway bridge)."""
    source = os.environ if environ is None else environ
    cfg = config_data if isinstance(config_data, dict) else {}
    raw = str(
        source.get(_JROS_GATEWAY_URL_ENV)
        or cfg.get("jros_gateway_url")
        or DEFAULT_JROS_GATEWAY_URL
    ).strip()
    return raw.rstrip("/") or DEFAULT_JROS_GATEWAY_URL


def _jros_gateway_api_key(environ: dict[str, str] | None = None) -> str:
    source = os.environ if environ is None else environ
    return str(source.get(_JROS_GATEWAY_KEY_ENV) or "").strip()


def _auth_headers() -> dict[str, str]:
    key = _jros_gateway_api_key()
    return {"Authorization": f"Bearer {key}"} if key else {}


def jros_gateway_health(timeout: float = 1.0, config_data=None) -> dict | None:
    """GET /v1/health from the configured JROS gateway.

    Returns the health payload dict when a live gateway answers, or None
    when unreachable — the availability signal api.backend_selector uses
    to light up the JROS option in the UI."""
    url = f"{jros_gateway_base_url(config_data)}/v1/health"
    req = urllib.request.Request(url, headers=_auth_headers(), method="GET")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
        return payload if isinstance(payload, dict) and payload.get("ok") else None
    except Exception:
        return None


def reset_jros_boot() -> None:
    """Drop every cached JROS boot so the next turn re-boots from disk config.

    JROS has no live model hot-swap (its client's model is fixed at
    construction time), so provider/model changes written to JROS's
    config.yaml (see api.ares_provider_sync) only apply after a re-boot.
    Covers both execution paths: the in-process fallback's cached boot is
    dropped here, and the gateway is asked to re-boot via POST /v1/reset.
    Best-effort: an unreachable gateway just means the next operator-run
    gateway boots fresh from disk anyway."""
    _reset_local_boot()
    url = f"{jros_gateway_base_url()}/v1/reset"
    req = urllib.request.Request(
        url, data=b"{}",
        headers={"Content-Type": "application/json", **_auth_headers()},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=5):
            pass
    except Exception:
        logger.debug("JROS gateway reset skipped (gateway unreachable)", exc_info=True)


# ── in-process fallback (no gateway, JROS on this machine) ──────────────

_JROS_DIR_ENV = "ARES_JROS_DIR"
_JROS_INSTANCE_ENV = "ARES_JROS_INSTANCE"

_BOOT_LOCK = threading.RLock()
_BOOT: Any | None = None


def local_jros_root() -> Path | None:
    """The local JROS checkout for in-process fallback, or None.

    Requires ``ARES_JROS_DIR`` to point at a directory containing
    ``jaeger_os/`` — never guessed, per the public-portability rule."""
    raw = os.environ.get(_JROS_DIR_ENV, "").strip()
    if not raw:
        return None
    root = Path(raw).expanduser().resolve()
    return root if (root / "jaeger_os").is_dir() else None


def _jros_instance_name() -> str | None:
    return os.environ.get(_JROS_INSTANCE_ENV, "").strip() or None


def _boot_jros() -> Any:
    """Boot and cache the local JROS pipeline for in-process turns.

    Guards the two ways this used to crash the web server: a missing
    instance no longer fires JROS's interactive setup wizard, and the
    exclusive instance lock held by a running JROS app/TUI becomes an
    actionable message instead of a bare "locked by pid" error."""
    global _BOOT
    with _BOOT_LOCK:
        if _BOOT is not None:
            return _BOOT
        root = local_jros_root()
        if root is None:
            raise RuntimeError(
                "ARES_JROS_DIR is not set (or does not contain jaeger_os/). "
                "Point it at your JROS checkout, or start a JROS gateway."
            )
        if str(root) not in sys.path:
            sys.path.insert(0, str(root))
        from jaeger_os.core.instance.instance import (
            InstanceLayout, default_instance_name, resolve_instance_dir)

        instance = _jros_instance_name() or default_instance_name()
        layout = InstanceLayout(resolve_instance_dir(instance))
        if not layout.exists():
            raise RuntimeError(
                f"no JROS instance named {instance!r} exists yet — run "
                "`jaeger setup` on the machine where JROS is installed first."
            )
        from jaeger_os.main import boot_for_tui

        try:
            with contextlib.redirect_stdout(sys.stderr):
                _BOOT = boot_for_tui(instance_name=instance, with_memory=True,
                                     warmup=False, prewarm_model=False)
        except RuntimeError as exc:
            if "lock" in str(exc).lower():
                raise RuntimeError(
                    "JROS is already running on this machine, so ARES can't "
                    "start a second copy (JROS allows one process per "
                    "instance). Close the running JROS app/TUI, or run "
                    "`jaeger gateway` instead of it so ARES can talk to JROS "
                    f"over the gateway. (Original error: {exc})"
                ) from exc
            raise
        return _BOOT


def _reset_local_boot() -> None:
    """Drop the in-process boot cache, releasing JROS's instance lock."""
    global _BOOT
    with _BOOT_LOCK:
        boot, _BOOT = _BOOT, None
    cleanup = getattr(boot, "cleanup", None) if boot is not None else None
    if callable(cleanup):
        try:
            cleanup()
        except Exception:
            logger.debug("Local JROS boot cleanup failed", exc_info=True)


def _run_local_jros_turn(msg_text: str, session_id: str, cancel_event: threading.Event) -> tuple[str, str, list[str]]:
    """One in-process JROS turn. Returns (text, error, tool_activity);
    boot/import failures come back as the error string so the caller can
    surface them as a normal apperror instead of a crashed stream."""
    try:
        boot = _boot_jros()
        if cancel_event.is_set():
            return "", "", []
        from jaeger_os.main import run_for_voice

        with contextlib.redirect_stdout(sys.stderr):
            result = run_for_voice(boot.client, str(msg_text or ""),
                                   session_key=f"webui:{session_id}")
    except Exception as exc:
        logger.warning("Local JROS turn failed: %s", exc, exc_info=True)
        return "", str(exc), []
    payload = dict(result or {}) if isinstance(result, dict) else {}
    error = str(payload.get("error") or "").strip()
    text = str(payload.get("text") or "").strip()
    tool_activity = payload.get("tool_activity") or []
    if not isinstance(tool_activity, list):
        tool_activity = [str(tool_activity)]
    return text, error, [str(item) for item in tool_activity if str(item).strip()]


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


def _merge_and_save_jros_turn(
    *,
    session_id: str,
    stream_id: str,
    msg_text: str,
    assistant_text: str,
    workspace: str,
    model: str,
    model_provider: str | None,
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
        selected_model_provider = str(model_provider or "").strip() or None
        assistant_msg = {
            "role": "assistant",
            "content": assistant_text,
            "timestamp": assistant_ts,
            "backend": "jros",
        }
        if selected_model_provider:
            assistant_msg["model_provider"] = selected_model_provider
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
                    if selected_model_provider:
                        msg["model_provider"] = selected_model_provider
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
        s.model = model or getattr(s, "model", "") or ""
        s.model_provider = selected_model_provider
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


def _jros_http_error_event(exc: urllib.error.HTTPError, err_body: str) -> dict:
    safe = _redact_text(err_body or str(exc))[:500]
    if exc.code == 401:
        key_configured = bool(_jros_gateway_api_key())
        return {
            "label": "JROS gateway authentication failed",
            "type": "jros_auth_error",
            "message": "JROS gateway rejected the request (HTTP 401).",
            "hint": (
                "Set ARES_JROS_GATEWAY_KEY to the same value as the gateway's "
                "JAEGER_GATEWAY_KEY."
                if not key_configured
                else "Check that ARES_JROS_GATEWAY_KEY matches the gateway's JAEGER_GATEWAY_KEY."
            ),
        }
    return {
        "label": "JROS gateway request failed",
        "type": "jros_http_error",
        "message": f"JROS gateway returned HTTP {exc.code}.",
        "hint": safe or _START_GATEWAY_HINT,
    }


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
    """Bridge a WebUI chat turn through the JROS gateway using the Hermes
    worker contract (same signature routes._select_chat_worker_target
    dispatches to)."""
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
        model=model or "",
        provider=model_provider or None,
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
        try:
            from api.config import get_config

            cfg = get_config()
        except Exception:
            cfg = {}
        base_url = jros_gateway_base_url(cfg)
        s = get_session(session_id)
        put_jros_event("context_status", {
            "session_id": session_id,
            "prefill": {"status": "jros", "source": "jros", "label": "JROS", "message_count": 0},
        })
        update_active_run(stream_id, phase="jros-request")

        url = f"{base_url}/v1/chat/completions"
        headers = {
            "Content-Type": "application/json",
            "Accept": "text/event-stream",
            **_auth_headers(),
        }
        body = {
            "model": model or "jros",
            "stream": True,
            # The gateway keeps per-session context server-side; ``user`` is
            # the session key, so each WebUI conversation stays its own JROS
            # conversation.
            "user": f"webui:{session_id}",
            "messages": [{"role": "user", "content": str(msg_text or "")}],
        }
        req = urllib.request.Request(
            url,
            data=json.dumps(body).encode("utf-8"),
            headers=headers,
            method="POST",
        )

        # Reuse the Hermes gateway SSE translators — the JROS gateway
        # deliberately speaks the same dialect.
        from api.gateway_chat import (
            _gateway_sse_delta,
            _gateway_stream_usage,
            _gateway_tool_progress_event,
        )

        final_text = ""
        turn_error = ""
        ran_locally = False
        sse_event = "message"
        try:
            resp_ctx = urllib.request.urlopen(req, timeout=600)
        except urllib.error.URLError as exc:
            # HTTPError means the gateway IS reachable and answered with an
            # error — no fallback, let the outer handler explain it.
            if isinstance(exc, urllib.error.HTTPError):
                raise
            if local_jros_root() is None:
                raise
            # No gateway, but JROS lives on this machine: run the turn
            # in-process (flip-the-toggle-and-it-works for the local case).
            ran_locally = True
            update_active_run(stream_id, phase="jros-local")
            final_text, turn_error, tool_activity = _run_local_jros_turn(
                msg_text, session_id, cancel_event
            )
            if cancel_event.is_set():
                put_jros_event("cancel", {"message": "Cancelled by user"})
                return
            for activity in tool_activity:
                if stream_id in STREAM_LIVE_TOOL_CALLS:
                    STREAM_LIVE_TOOL_CALLS[stream_id].append(
                        {"name": "jros", "args": {"activity": activity}, "done": True}
                    )
                put_jros_event("tool", {
                    "event_type": "tool.completed",
                    "name": "jros",
                    "preview": activity,
                    "is_error": False,
                })
            if final_text:
                STREAM_PARTIAL_TEXT[stream_id] = final_text
                usage["output_tokens"] = max(1, len(final_text.split()))
                put_jros_event("token", {"text": final_text})
            resp_ctx = None
        if resp_ctx is not None:
            with resp_ctx as resp:
                for raw_line in resp:
                    if cancel_event.is_set():
                        put_jros_event("cancel", {"message": "Cancelled by user"})
                        return
                    line = raw_line.decode("utf-8", errors="replace").strip()
                    if not line:
                        sse_event = "message"
                        continue
                    if line.startswith("event:"):
                        sse_event = line[6:].strip() or "message"
                        continue
                    if not line.startswith("data:"):
                        continue
                    data = line[5:].strip()
                    if data == "[DONE]":
                        break
                    try:
                        payload = json.loads(data)
                    except json.JSONDecodeError:
                        continue
                    if sse_event == "jros.status":
                        update_active_run(stream_id, phase="jros-running")
                        sse_event = "message"
                        continue
                    if sse_event == "jros.error":
                        turn_error = str(payload.get("message") or "JROS turn failed")
                        sse_event = "message"
                        continue
                    if sse_event == "hermes.tool.progress":
                        translated = _gateway_tool_progress_event(payload)
                        if translated:
                            event_name, event_payload = translated
                            if event_name != "reasoning" and stream_id in STREAM_LIVE_TOOL_CALLS:
                                STREAM_LIVE_TOOL_CALLS[stream_id].append({
                                    "name": event_payload.get("name"),
                                    "args": event_payload.get("args") or {},
                                    "done": event_payload.get("event_type") == "tool.completed",
                                })
                            # The WebUI stream contract uses "tool" for progress rows.
                            put_jros_event("tool" if event_name in ("tool", "tool_complete") else event_name, event_payload)
                            update_active_run(stream_id, phase="jros-tool", latest_tool=event_payload.get("name"))
                        sse_event = "message"
                        continue
                    delta = _gateway_sse_delta(payload)
                    if delta:
                        final_text += delta
                        if stream_id in STREAM_PARTIAL_TEXT:
                            STREAM_PARTIAL_TEXT[stream_id] += delta
                        put_jros_event("token", {"text": delta})
                    usage.update({k: v for k, v in _gateway_stream_usage(payload).items() if v})

        if cancel_event.is_set():
            put_jros_event("cancel", {"message": "Cancelled by user"})
            return
        assistant_text = final_text.strip()
        if turn_error and not assistant_text:
            put_jros_event("apperror", {
                "label": "JROS request failed",
                "type": "jros_local_error" if ran_locally else "jros_error",
                "message": _redact_text(turn_error)[:500],
                "hint": (
                    "ARES ran JROS in-process on this machine (no gateway was reachable)."
                    if ran_locally
                    else "ARES reached the JROS gateway. Check JROS provider config/quota if the model call failed."
                ),
            })
            return
        if not assistant_text:
            put_jros_event("apperror", {
                "label": "JROS returned no response",
                "type": "jros_empty_response",
                "message": "JROS returned no assistant message for this turn.",
                "hint": (
                    "JROS ran on this machine (in-process) but produced no reply. Check its model provider."
                    if ran_locally
                    else f"Check the JROS gateway at {base_url} and its model provider."
                ),
            })
            return
        saved_session = _merge_and_save_jros_turn(
            session_id=session_id,
            stream_id=stream_id,
            msg_text=str(msg_text or ""),
            assistant_text=assistant_text,
            workspace=str(workspace),
            model=model or "",
            model_provider=model_provider,
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
    except urllib.error.HTTPError as exc:
        try:
            err_body = exc.read().decode("utf-8", errors="replace")
        except Exception:
            err_body = ""
        put_jros_event("apperror", _jros_http_error_event(exc, err_body))
    except urllib.error.URLError as exc:
        put_jros_event("apperror", {
            "label": "JROS gateway unreachable",
            "type": "jros_gateway_offline",
            "message": _redact_text(str(exc.reason if hasattr(exc, "reason") else exc))[:500],
            "hint": _START_GATEWAY_HINT,
        })
    except Exception as exc:
        safe = _redact_text(str(exc))[:500]
        put_jros_event("apperror", {
            "label": "JROS request failed",
            "type": "jros_gateway_error",
            "message": safe or "JROS request failed.",
            "hint": _START_GATEWAY_HINT,
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


# The worker name routes.py dispatches to (kept from the old bridge).
run_jros_streaming = _run_jros_chat_streaming
