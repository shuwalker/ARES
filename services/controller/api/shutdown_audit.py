"""Sanitized shutdown diagnostics independent of the HTTP server."""

from __future__ import annotations

import logging
import os
import re
import threading


logger = logging.getLogger("server")
_LOGGED = False
_CONTROL = re.compile(r"[\x00-\x1f\x7f]+")


def safe_log_value(value, *, default: str = "unknown", max_len: int = 160) -> str:
    try:
        text = str(value) if value is not None else default
    except Exception:
        return default
    text = _CONTROL.sub("?", text).strip()
    return f"{text[:max_len]}…" if len(text) > max_len else (text or default)


def log_shutdown_audit(reason: str = "uvicorn_exit") -> None:
    global _LOGGED
    if _LOGGED:
        return
    active = []
    try:
        from api.models import LOCK, SESSIONS

        with LOCK:
            rows = list(SESSIONS.items())
        for session_id, session in rows:
            stream_id = getattr(session, "active_stream_id", None)
            if stream_id:
                active.append(
                    "sid=%s stream=%s pending=%s"
                    % (
                        safe_log_value(session_id),
                        safe_log_value(stream_id),
                        bool(getattr(session, "pending_user_message", None)),
                    )
                )
    except Exception:
        logger.debug("Failed to collect active-session shutdown audit state", exc_info=True)
    _LOGGED = True
    thread = threading.current_thread()
    logger.info(
        "[shutdown-audit] reason=%s pid=%s thread=%s(%s) active_sessions=[%s]",
        safe_log_value(reason),
        os.getpid(),
        safe_log_value(thread.name),
        thread.ident,
        "; ".join(active) if active else "none",
    )


__all__ = ["log_shutdown_audit", "safe_log_value"]
