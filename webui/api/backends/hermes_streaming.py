"""Hermes streaming worker for ARES WebUI.

Spawns ``hermes chat -q "..." -Q --yolo --source webui`` as a subprocess,
pipes stdout to the SSE stream channel, and handles session state updates.

The function signature matches the Ares worker contract used by
``chat_runtime._select_chat_worker_target()``.
"""

from __future__ import annotations

import logging
import os
import re
import subprocess
import threading
import time
from typing import Any

from api.streaming import (
    RunJournalWriter,
    STREAMS,
    STREAMS_LOCK,
    CANCEL_FLAGS,
    STREAM_PARTIAL_TEXT,
    register_active_run,
    unregister_stream_owner,
)

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Hermes session ID persistence (maps ARES session -> Hermes session)
# ---------------------------------------------------------------------------

_HERMES_SESSION_MAP: dict[str, str] = {}


def _session_exists_in_worker_store(session_id: str) -> bool:
    """True when the Hermes agent already owns a session with this exact id.

    Sessions started in the terminal are keyed in ``state.db`` by the same id
    ARES lists them under, so the id itself is the resume handle.
    """
    if not session_id:
        return False
    try:
        from api.models import _agent_state_db_path, open_state_db_readonly
        from contextlib import closing

        db_path = _agent_state_db_path()
        if db_path is None:
            return False
        with closing(open_state_db_readonly(db_path)) as conn:
            row = conn.execute(
                "SELECT 1 FROM sessions WHERE id = ? LIMIT 1", (session_id,)
            ).fetchone()
        return bool(row)
    except Exception:
        # Resume is an optimization; never block a turn on a probe failure.
        return False


def _get_hermes_session_id(ares_session_id: str) -> str | None:
    """Look up the Hermes session ID for an ARES session, if any.

    The in-memory map only covers sessions this process started, so it is empty
    for imported terminal history and after any restart. Falling back to the
    worker's own store is what makes a CLI session *continuable* rather than
    forked: without it the agent silently began a brand-new session on every
    reply, which is why continuing imported history never worked.
    """
    mapped = _HERMES_SESSION_MAP.get(ares_session_id)
    if mapped:
        return mapped
    if _session_exists_in_worker_store(ares_session_id):
        # Cache so the next turn skips the probe.
        _HERMES_SESSION_MAP[ares_session_id] = ares_session_id
        return ares_session_id
    return None


def _store_hermes_session_id(ares_session_id: str, hermes_session_id: str) -> None:
    """Store the Hermes session ID for later resume."""
    _HERMES_SESSION_MAP[ares_session_id] = hermes_session_id


def _finish_hermes_stream(
    stream_id: str,
    session_id: str,
    q: Any,
    run_journal: Any,
    cancel_event: threading.Event,
    accumulated_text: str = "",
    user_message: str = "",
) -> None:
    """Clean up the stream channel and signal completion.

    Persists user + assistant messages to the session, then signals done.
    """
    cancel_event.set()
    with STREAMS_LOCK:
        CANCEL_FLAGS.pop(stream_id, None)
        STREAM_PARTIAL_TEXT.pop(stream_id, None)
        STREAMS.pop(stream_id, None)

    # Mark the stream as no longer active
    try:
        from api.streaming import unregister_active_run
        unregister_active_run(stream_id)
    except Exception:
        pass

    # Persist messages to the session
    if accumulated_text.strip() or user_message.strip():
        try:
            from api.models import get_session
            session = get_session(session_id)
            if session is not None:
                existing = list(getattr(session, "messages", None) or [])
                latest = existing[-1] if existing and isinstance(existing[-1], dict) else {}
                if user_message.strip() and not (
                    latest.get("role") == "user"
                    and " ".join(str(latest.get("content") or "").split())
                    == " ".join(user_message.split())
                ):
                    session.messages.append({
                        "role": "user",
                        "content": user_message,
                        "timestamp": int(time.time()),
                    })
                if accumulated_text.strip():
                    session.messages.append({
                        "role": "assistant",
                        "content": accumulated_text.strip(),
                        "timestamp": int(time.time()),
                    })
                if getattr(session, "active_stream_id", None) == stream_id:
                    session.active_stream_id = None
                    session.pending_user_message = None
                    session.pending_attachments = []
                    session.pending_started_at = None
                    session.pending_user_source = None
                session.save()
                logger.info("Hermes worker persisted messages to session %s", session_id[:8])
        except Exception:
            logger.error("Hermes worker failed to persist messages", exc_info=True)

    terminal_payload = {"stream_id": stream_id, "session_id": session_id}
    terminal_event_id = None
    if run_journal is not None:
        try:
            terminal_entry = run_journal.append_sse_event("stream_end", terminal_payload)
            if isinstance(terminal_entry, dict):
                terminal_event_id = terminal_entry.get("event_id")
        except Exception:
            logger.debug("Failed to persist Hermes terminal stream event", exc_info=True)

    try:
        terminal_item = (
            ("stream_end", terminal_payload, terminal_event_id)
            if terminal_event_id
            else ("stream_end", terminal_payload)
        )
        q.put_nowait(terminal_item)
        q.put_nowait(("done", {"session_id": session_id, "stream_id": stream_id}))
    except Exception:
        pass

    unregister_stream_owner(stream_id)

    if run_journal is not None:
        try:
            run_journal.close()
        except Exception:
            pass

    logger.info("Hermes worker finished: session=%s stream=%s", session_id[:8], stream_id[:8])


def run_hermes_streaming(
    session_id: str,
    msg_text: str,
    model: str,
    workspace: str,
    stream_id: str,
    attachments: list | None = None,
    *,
    model_provider: str | None = None,
    goal_related: bool = False,
    moa_config: dict | None = None,
) -> None:
    """Bridge a WebUI chat turn through Hermes Agent CLI.

    Spawns ``hermes chat -q`` as a subprocess, streams output to the SSE
    channel registered in ``STREAMS[stream_id]``, and updates session state.
    """
    from api.backends.hermes import _hermes_cli

    q = STREAMS.get(stream_id)
    if q is None:
        unregister_stream_owner(stream_id)
        return

    register_active_run(
        stream_id,
        session_id=session_id,
        started_at=time.time(),
        phase="hermes-starting",
        workspace=str(workspace),
        model=model or "",
        provider=model_provider or None,
        backend="hermes",
    )

    cancel_event = threading.Event()
    with STREAMS_LOCK:
        CANCEL_FLAGS[stream_id] = cancel_event
        STREAM_PARTIAL_TEXT[stream_id] = ""

    try:
        run_journal = RunJournalWriter(session_id, stream_id)
    except Exception:
        run_journal = None
        logger.debug("Failed to initialize Hermes run journal for stream %s", stream_id, exc_info=True)

    # ---- Helper to emit events to the stream channel ----
    def emit(event: str, data: Any = None) -> None:
        if cancel_event.is_set() and event not in ("cancel", "error", "ended", "done"):
            return
        try:
            if hasattr(q, "subscribe_with_snapshot"):
                event_id = None
                if run_journal is not None:
                    try:
                        event_id = run_journal.append_sse_event(event, data)
                    except Exception:
                        pass
                if event_id and hasattr(q, "note_last_event_id"):
                    q.note_last_event_id(event_id)
                queue_item = (event, data, event_id) if event_id else (event, data)
            else:
                queue_item = (event, data)
            q.put_nowait(queue_item)
        except Exception:
            logger.debug("Failed to emit Hermes stream event", exc_info=True)

    # ---- Build the Hermes CLI command ----
    cli = _hermes_cli()
    if not cli:
        emit("error", {"type": "hermes_unavailable", "message": "Hermes Agent CLI not found on $PATH."})
        _finish_hermes_stream(stream_id, session_id, q, run_journal, cancel_event, accumulated_text="", user_message=msg_text)
        return

    from api.backends.hermes import resolve_hermes_defaults

    default_model, default_provider = resolve_hermes_defaults()
    effective_model = (model or "").strip() or default_model
    # model_provider is often the ARES backend id (hermes_local, ollama_local); only use it if it looks like a Hermes provider.
    ares_backend_ids = {
        "hermes_local", "jros_local", "claude_local", "codex_local", "gemini_local",
        "grok_local", "opencode_local", "cursor_local", "pi_local", "openai_cloud",
        "xai_cloud", "ollama_local",
    }
    if model_provider and model_provider not in ares_backend_ids:
        effective_provider = model_provider
    else:
        effective_provider = default_provider

    # Chat tab is a pure worker console: send the user message unchanged.
    # Companion SI packaging lives on the Companion surface later — not here.
    args = [
        cli, "chat", "-q", msg_text, "-Q", "--yolo", "--source", "webui",
        "-m", effective_model, "--provider", effective_provider,
    ]

    # Resume session if we have a previous hermes session ID
    hermes_session_id = _get_hermes_session_id(session_id)
    if hermes_session_id:
        args.extend(["--resume", hermes_session_id])

    effective_workspace = workspace or os.path.expanduser("~")

    # Build environment
    env = dict(os.environ)
    env["HERMES_HOME"] = os.environ.get("HERMES_HOME", os.path.expanduser("~/.hermes"))

    logger.info("Hermes worker cmd: %s", " ".join(args))

    # ---- Register as running ----
    register_active_run(
        stream_id,
        session_id=session_id,
        started_at=time.time(),
        phase="hermes-running",
        workspace=str(workspace),
        model=model or "",
        provider=model_provider or None,
        backend="hermes",
    )

    # Signal: turn started
    emit("server_turn_started", {"stream_id": stream_id})

    accumulated_text = ""
    proc: subprocess.Popen | None = None

    try:
        logger.warning("Hermes worker: spawning subprocess with args=%s cwd=%s", args[:4], effective_workspace)
        proc = subprocess.Popen(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            cwd=effective_workspace,
            env=env,
        )
        logger.warning("Hermes worker process started: pid=%s", proc.pid)

        # Drain stderr in a separate thread to avoid deadlock
        stderr_lines: list[str] = []

        def _drain_stderr() -> None:
            try:
                if proc.stderr is not None:
                    for line in proc.stderr:
                        stderr_lines.append(line.decode("utf-8", errors="replace").rstrip("\n\r"))
            except Exception:
                pass

        stderr_thread = threading.Thread(target=_drain_stderr, daemon=True)
        stderr_thread.start()

        # Read stdout line by line
        if proc.stdout is None:
            emit("error", {"type": "hermes_error", "message": "Hermes process produced no stdout."})
            proc.wait(timeout=10)
            _finish_hermes_stream(stream_id, session_id, q, run_journal, cancel_event, accumulated_text="", user_message=msg_text)
            return

        for line in proc.stdout:
            if cancel_event.is_set():
                logger.info("Hermes worker cancelled: stream=%s", stream_id[:8])
                proc.terminate()
                break

            decoded = line.decode("utf-8", errors="replace").rstrip("\n\r")

            # Parse session_id from Hermes output (comes on stderr now, but check both)
            session_match = re.match(r"^session_id:\s*(\S+)", decoded)
            if session_match:
                _store_hermes_session_id(session_id, session_match.group(1))
                continue

            # Skip noise lines
            if re.match(r"^\[\d{4}-\d{2}-\d{2}T", decoded):
                continue
            if re.match(r"^\[(tool|hermes|paperclip)\]", decoded, re.IGNORECASE):
                tool_name = re.match(r"^\[(?:tool|hermes)\]\s*(\S+)", decoded, re.IGNORECASE)
                if tool_name:
                    emit("tool", {"label": tool_name.group(1)})
                continue
            if re.match(r"^\[done\]", decoded, re.IGNORECASE):
                continue

            # Clean leading chat bubble
            cleaned = re.sub(r"^[\s]*┊\s*💬\s*", "", decoded).strip()
            cleaned = re.sub(r"^\[done\]\s*", "", cleaned).strip()

            if not cleaned:
                continue

            accumulated_text += cleaned + "\n"
            STREAM_PARTIAL_TEXT[stream_id] = accumulated_text

            # Stream text delta
            emit("token", {"text": cleaned + "\n"})

        # Wait for process to finish
        proc.wait(timeout=60)

        # Wait for stderr thread to finish
        stderr_thread.join(timeout=5)

        # Parse session_id from stderr lines
        for line in stderr_lines:
            sid_match = re.match(r"^session_id:\s*(\S+)", line)
            if sid_match:
                _store_hermes_session_id(session_id, sid_match.group(1))
                break

        if proc.returncode != 0:
            error_lines = [
                ln for ln in stderr_lines
                if re.search(r"error|exception|traceback|failed", ln, re.IGNORECASE)
                and not re.search(r"INFO|DEBUG|warn", ln, re.IGNORECASE)
            ]
            if error_lines:
                emit("error", {"type": "hermes_error", "message": "\n".join(error_lines[:5])})

    except subprocess.TimeoutExpired:
        if proc is not None:
            proc.kill()
        logger.warning("Hermes worker timed out: session=%s stream=%s", session_id[:8], stream_id[:8])
        emit("error", {"type": "hermes_timeout", "message": "Hermes turn timed out."})
    except Exception as exc:
        logger.error("Hermes worker failed: %s", exc, exc_info=True)
        emit("error", {"type": "hermes_exception", "message": str(exc)})
    finally:
        logger.warning("Hermes worker entering finally: session=%s stream=%s proc_returncode=%s text_len=%d stderr_lines=%d",
                       session_id[:8], stream_id[:8],
                       proc.returncode if proc else "no_proc",
                       len(accumulated_text),
                       len(stderr_lines) if 'stderr_lines' in dir() else -1)
        _finish_hermes_stream(stream_id, session_id, q, run_journal, cancel_event, accumulated_text=accumulated_text, user_message=msg_text)
