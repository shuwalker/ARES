"""Default-off JROS bridge for browser-originated ARES chat turns.

This is intentionally shaped like ``api.gateway_chat._run_gateway_chat_streaming``:
/api/chat/start still creates a normal local WebUI stream, /api/chat/stream still
receives WebUI SSE event names, and the final turn is persisted back into the
same WebUI session model. The only swapped piece is execution: instead of
calling Hermes Gateway/OpenAI-compatible chat, this talks to an existing JROS
install over the supported ``jaeger bridge`` stdio NDJSON protocol via the
stdlib-only ``api.jros_client`` helper.

ARES does not pip-install JROS into its venv and does not clone a second JROS
copy. It drives the operator's existing ``~/jaeger`` install, or the install
pointed to by ``JAEGER_HOME`` / ``ARES_JAEGER_HOME``.
"""
from __future__ import annotations

import contextlib
import json
import logging
import os
import selectors
import subprocess
import sys
import threading
import time
from typing import Any

from api.jros_paths import jaeger_home, jaeger_launcher, jros_instance_name, jros_source_root

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
_BOOT: Any | None = None  # legacy source-checkout boot cache
_JROS_CLIENT: Any | None = None


def _jros_repo_root() -> Any:
    """Compatibility wrapper for source-tree character/assets access."""
    return jros_source_root()


def _jaeger_home() -> Any:
    return jaeger_home()


def _jaeger_launcher() -> Any:
    return jaeger_launcher()


def is_jros_bridge_available() -> bool:
    """Return True when ARES can spawn the supported JROS bridge.

    This performs a real probe — not just a filesystem check — so the
    availability result matches what a chat turn would actually experience.
    The probe checks:
      1. The launcher binary exists and is executable.
      2. A test bridge subprocess can boot and return its ``ready`` handshake
         within 10 seconds (same contract Hermes gets for free by being
         in-process).
      3. The test subprocess is killed after the handshake regardless.

    This mirrors how Hermes availability works: Hermes is "available" because
    it's in-process and will raise immediately if broken. JROS should prove
    the same — a file on disk doesn't mean the bridge can actually boot.
    """
    launcher = _jaeger_launcher()
    if not (launcher.exists() and os.access(launcher, os.X_OK)):
        logger.debug("JROS launcher not found or not executable: %s", launcher)
        return False

    # Real probe: spawn the bridge, wait for the ready handshake, then kill it.
    # This is the same contract a real chat turn uses (JrosClient.start()),
    # so if this fails, a chat turn would fail too.
    # Resolve instance name the same way a real turn would.
    instance = _jros_instance_name()
    env = os.environ.copy()
    command = [str(launcher), "bridge"]
    if instance:
        env["JAEGER_INSTANCE_NAME"] = instance
        command.append(instance)

    try:
        proc = subprocess.Popen(
            command,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,  # capture stderr instead of discarding
            text=True,
            bufsize=1,
            env=env,
        )
    except Exception as exc:
        logger.warning("JROS bridge probe: failed to spawn %s: %s", launcher, exc)
        return False

    try:
        ready = None
        stderr_lines: list[str] = []
        deadline = time.time() + 10  # 10s handshake timeout (same as JrosClient)

        while time.time() < deadline:
            # Check if process exited
            if proc.poll() is not None:
                # Read any remaining stderr for diagnostics
                remaining_err = (proc.stderr.read() or "") if proc.stderr else ""
                if remaining_err:
                    stderr_lines.append(remaining_err)
                break

            # Read stdout lines (ready handshake comes on stdout)
            result_holder: dict = {"ready": None, "error": None}

            def _read_ready():
                try:
                    for line in proc.stdout:
                        line = line.strip()
                        if not line:
                            continue
                        try:
                            obj = json.loads(line)
                        except (json.JSONDecodeError, ValueError):
                            continue
                        if not isinstance(obj, dict):
                            continue
                        if obj.get("type") == "ready":
                            result_holder["ready"] = obj
                            return
                        if obj.get("type") == "fatal":
                            result_holder["error"] = str(obj.get("error", "bridge fatal"))
                            return
                except Exception as exc:
                    result_holder["error"] = str(exc)

            reader = threading.Thread(target=_read_ready, daemon=True)
            reader.start()
            reader.join(timeout=max(0.1, deadline - time.time()))

            if result_holder["ready"] is not None:
                ready = result_holder["ready"]
                break
            if result_holder["error"] is not None:
                logger.warning(
                    "JROS bridge probe: bridge reported fatal during handshake: %s",
                    result_holder["error"],
                )
                break
        else:
            logger.warning("JROS bridge probe: timed out waiting for ready handshake")

        # Drain stderr for diagnostics (non-blocking)
        try:
            if proc.stderr and not proc.stderr.closed:
                sel = selectors.PollSelector()
                sel.register(proc.stderr, selectors.EVENT_READ)
                for _ in range(50):  # max 50 lines
                    events = sel.select(timeout=0.05)
                    if not events:
                        break
                    err_line = proc.stderr.readline()
                    if err_line:
                        stderr_lines.append(err_line.rstrip())
                    else:
                        break
                sel.unregister(proc.stderr)
        except Exception:
            pass

        if stderr_lines:
            logger.debug("JROS bridge probe stderr: %s", "\\n".join(stderr_lines[-5:]))

        if ready is not None:
            instance_name = ready.get("instance", "?")
            model_name = ready.get("model", "?")
            logger.info(
                "JROS bridge probe succeeded: instance=%s model=%s",
                instance_name,
                model_name,
            )
            return True

        logger.warning("JROS bridge probe: no ready handshake received")
        return False

    finally:
        # Always kill the probe subprocess
        if proc.poll() is None:
            try:
                proc.terminate()
                proc.wait(timeout=3)
            except Exception:
                try:
                    proc.kill()
                except Exception:
                    pass


def _jros_instance_name() -> str | None:
    return jros_instance_name()


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


def _get_jros_client() -> Any:
    """Start or reuse the supported single JROS bridge client."""
    global _JROS_CLIENT
    with _BOOT_LOCK:
        if _JROS_CLIENT is not None:
            return _JROS_CLIENT
        from api.jros_client import JrosClient

        if not is_jros_bridge_available():
            raise RuntimeError(
                f"JROS bridge launcher not found at {_jaeger_launcher()}. "
                "Install JROS first (curl -fsSL https://raw.githubusercontent.com/JenkinsRobotics/JROS/master/scripts/install.sh | bash) "
                "or set JAEGER_HOME/ARES_JAEGER_HOME."
            )
        _JROS_CLIENT = JrosClient(
            jaeger_home=str(_jaeger_home()),
            instance=_jros_instance_name(),
        )
        _JROS_CLIENT.start()
        return _JROS_CLIENT


def reset_jros_boot() -> None:
    """Drop cached JROS bridge/source clients so the next turn starts fresh."""
    global _BOOT, _JROS_CLIENT
    with _BOOT_LOCK:
        _BOOT = None
        if _JROS_CLIENT is not None:
            try:
                _JROS_CLIENT.close()
            except Exception:
                logger.debug("Failed to close cached JROS client", exc_info=True)
        _JROS_CLIENT = None


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


def _jros_fallback_chain() -> list[dict]:
    """Read the fallback_providers chain already synced into JROS's config.

    api.ares_provider_sync.sync_fallback_chain() writes this list (mirrored
    from Hermes's own fallback_providers, translated to JROS-runnable
    providers). JROS itself never reads it — nothing about "no provider
    negotiation" in jaeger_os changes because of this list existing — so
    this bridge is what actually walks it on failure.
    """
    try:
        from api.ares_provider_sync import load_yaml_config, resolve_jros_config_path

        cfg = load_yaml_config(resolve_jros_config_path())
        chain = cfg.get("fallback_providers") if isinstance(cfg, dict) else None
        return [e for e in chain if isinstance(e, dict) and e.get("provider") and e.get("model")] if isinstance(chain, list) else []
    except Exception:
        logger.debug("Failed to read JROS fallback chain", exc_info=True)
        return []


def _apply_jros_provider_entry(entry: dict) -> None:
    """Write a fallback entry into JROS's external_model config and reboot.

    Raises on failure to write config; the caller decides whether to try the
    next entry or give up.
    """
    from api.ares_provider_sync import load_yaml_config, resolve_jros_config_path, save_yaml_config

    path = resolve_jros_config_path()
    cfg = load_yaml_config(path)
    external_model = cfg.get("external_model")
    if not isinstance(external_model, dict):
        external_model = {}
        cfg["external_model"] = external_model
    external_model["enabled"] = True
    external_model["provider"] = entry["provider"]
    external_model["model"] = entry["model"]
    if entry.get("base_url"):
        external_model["base_url"] = entry["base_url"]
    if entry.get("key_env") or entry.get("api_key_env"):
        external_model["api_key_env"] = entry.get("key_env") or entry.get("api_key_env")
    save_yaml_config(path, cfg)
    reset_jros_boot()


def _attempt_jros_turn(msg_text: str, session_id: str, cancel_event: threading.Event | None) -> tuple[str, str, list[str]]:
    """One attempt against the supported JROS jaeger bridge.

    Returns (assistant_text, error, tool_activity). Raises on hard bridge boot
    failures so the fallback loop can distinguish "JROS reported an error"
    from "ARES could not reach JROS".
    """
    if cancel_event is not None and cancel_event.is_set():
        return "", "", []
    client = _get_jros_client()
    tool_activity: list[str] = []

    def on_event(frame: dict) -> None:
        if not isinstance(frame, dict):
            return
        preview = (
            frame.get("preview")
            or frame.get("message")
            or frame.get("name")
            or frame.get("type")
            or frame
        )
        tool_activity.append(str(preview))

    result = client.turn(
        str(msg_text or ""),
        session=f"webui:{session_id}",
        on_event=on_event,
    )
    return _assistant_text_from_jros_result({
        "text": (result or {}).get("text") if isinstance(result, dict) else "",
        "error": (result or {}).get("error") if isinstance(result, dict) else "",
        "tool_activity": tool_activity,
    })


def _run_jros_turn_with_fallback(
    msg_text: str, session_id: str, cancel_event: threading.Event, put_jros_event
) -> tuple[str, str, list[str]]:
    """Try the active JROS provider; on failure, walk the synced fallback
    chain (each attempt costs a reboot) until one succeeds or it's exhausted.

    Mirrors Hermes's exhaust-the-chain behavior, implemented here because
    JROS has no native fallback/retry concept of its own.
    """
    try:
        assistant_text, error, tool_activity = _attempt_jros_turn(msg_text, session_id, cancel_event)
        if not error and assistant_text:
            return assistant_text, error, tool_activity
        last_error = error or "JROS returned no response"
    except Exception as exc:
        last_error = str(exc)
        logger.warning("JROS turn failed on active provider: %s", last_error, exc_info=True)

    chain = _jros_fallback_chain()
    if not chain:
        return "", last_error, []

    for i, entry in enumerate(chain):
        if cancel_event.is_set():
            return "", last_error, []
        put_jros_event("apperror", {
            "label": "JROS falling back",
            "type": "jros_fallback",
            "message": f"{entry['provider']}/{entry['model']} failed; trying fallback {i + 1}/{len(chain)}: "
                       f"switching to next configured provider.",
            "hint": last_error,
        })
        try:
            _apply_jros_provider_entry(entry)
            assistant_text, error, tool_activity = _attempt_jros_turn(msg_text, session_id, cancel_event)
            if not error and assistant_text:
                return assistant_text, error, tool_activity
            last_error = error or "JROS returned no response"
        except Exception as exc:
            last_error = str(exc)
            logger.warning("JROS fallback attempt %s (%s/%s) failed: %s", i + 1, entry.get("provider"), entry.get("model"), last_error, exc_info=True)

    return "", f"All JROS providers exhausted. Last error: {last_error}", []


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
        s = get_session(session_id)
        put_jros_event("context_status", {
            "session_id": session_id,
            "prefill": {"status": "jros", "source": "jros", "label": "JROS", "message_count": 0},
        })
        update_active_run(stream_id, phase="jros-booting")
        update_active_run(stream_id, phase="jros-request")
        assistant_text, error, tool_activity = _run_jros_turn_with_fallback(
            msg_text, session_id, cancel_event, put_jros_event
        )
        if cancel_event.is_set():
            put_jros_event("cancel", {"message": "Cancelled by user"})
            return
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
                "hint": "Check the active JROS instance and model provider.",
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
    except Exception as exc:
        safe = _redact_text(str(exc))[:500]
        put_jros_event("apperror", {
            "label": "JROS request failed",
            "type": "jros_bridge_error",
            "message": safe or "JROS request failed.",
            "hint": "Check the JROS bridge launcher, active instance, and provider health.",
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
