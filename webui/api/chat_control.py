"""Transport-neutral controls for an active chat run."""

from __future__ import annotations

from typing import Any


class ChatControlError(RuntimeError):
    def __init__(self, message: str, status_code: int = 400):
        super().__init__(message)
        self.status_code = status_code


def steer_session(payload: dict[str, Any]) -> dict[str, Any]:
    from api import config
    from api.models import get_session

    session_id = str(payload.get("session_id") or "").strip()
    text = str(payload.get("text") or "").strip()
    if not session_id:
        raise ChatControlError("session_id required")
    if not text:
        raise ChatControlError("text required")

    with config.SESSION_AGENT_CACHE_LOCK:
        cached = config.SESSION_AGENT_CACHE.get(session_id)
    if not cached:
        try:
            session = get_session(session_id)
            stream_id = getattr(session, "active_stream_id", None) or None
        except KeyError:
            stream_id = None
        if stream_id:
            with config.ACTIVE_RUNS_LOCK:
                run = dict((config.ACTIVE_RUNS or {}).get(str(stream_id)) or {})
            if run.get("backend") == "gateway":
                return {
                    "accepted": False,
                    "fallback": "gateway_steer_queued",
                    "stream_id": stream_id,
                }
        return {"accepted": False, "fallback": "no_cached_agent", "stream_id": None}

    agent = cached[0]
    if not hasattr(agent, "steer"):
        return {"accepted": False, "fallback": "agent_lacks_steer", "stream_id": None}
    try:
        session = get_session(session_id)
    except KeyError as exc:
        raise ChatControlError("Session not found", 404) from exc
    stream_id = getattr(session, "active_stream_id", None) or None
    if not stream_id:
        return {"accepted": False, "fallback": "no_active_stream", "stream_id": None}
    with config.STREAMS_LOCK:
        if stream_id not in config.STREAMS:
            return {"accepted": False, "fallback": "stream_not_running", "stream_id": stream_id}
    accepted = bool(agent.steer(text))
    return {
        "accepted": accepted,
        "fallback": None if accepted else "steer_rejected",
        "stream_id": stream_id,
    }


__all__ = ["ChatControlError", "steer_session"]
