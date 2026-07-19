"""ARES Backend Adapter Base — defines the contract for any agent backend.

Pure ARES code. Backends are never modified — ARES wraps them.
Each backend is just {name}_{deployment}. No roles, no opinions.
"""
from __future__ import annotations

from abc import ABC, abstractmethod
import logging
import threading
import time
from typing import Any, Dict, List


logger = logging.getLogger(__name__)


def run_agentic_backend_streaming(
    session_id: str,
    message: str,
    model: str,
    workspace: str,
    stream_id: str,
    attachments: list | None = None,
    *,
    model_provider: str | None = None,
    goal_related: bool = False,
) -> None:
    """Bridge synchronous adapter turns into the canonical stream contract."""

    del workspace, attachments, goal_related
    from api.run_journal import RunJournalWriter
    from api.streaming import (
        CANCEL_FLAGS,
        STREAM_LAST_EVENT_ID,
        STREAM_PARTIAL_TEXT,
        STREAMS,
        STREAMS_LOCK,
        register_active_run,
        unregister_active_run,
        unregister_stream_owner,
    )

    channel = STREAMS.get(stream_id)
    if channel is None:
        unregister_stream_owner(stream_id)
        return

    cancel_event = threading.Event()
    with STREAMS_LOCK:
        CANCEL_FLAGS[stream_id] = cancel_event
        STREAM_PARTIAL_TEXT[stream_id] = ""
    register_active_run(stream_id, session_id=session_id, started_at=time.time(), phase="adapter")
    try:
        journal = RunJournalWriter(session_id, stream_id)
    except Exception:
        journal = None
        logger.debug("Could not initialize adapter journal for %s", stream_id, exc_info=True)

    def publish(event: str, data: dict) -> None:
        event_id = None
        if journal is not None:
            try:
                entry = journal.append_sse_event(event, data)
                event_id = str((entry or {}).get("event_id") or "") or None
            except Exception:
                logger.debug("Could not journal adapter event %s", event, exc_info=True)
        if event_id:
            STREAM_LAST_EVENT_ID[stream_id] = event_id
        try:
            channel.put_nowait((event, data, event_id) if event_id else (event, data))
        except Exception:
            logger.debug("Could not publish adapter event %s", event, exc_info=True)

    try:
        from api.chat_runtime import _backend_for_session
        from api.models import get_session

        session = get_session(session_id)
        backend = _backend_for_session(session)
        normalized_message = " ".join(message.split())
        existing = list(getattr(session, "messages", None) or [])
        latest = existing[-1] if existing and isinstance(existing[-1], dict) else {}
        if latest.get("role") != "user" or " ".join(
            str(latest.get("content") or "").split()
        ) != normalized_message:
            session.messages.append({"role": "user", "content": message, "timestamp": int(time.time())})
            session.save()
        result = backend.run_turn(
            message,
            session_id,
            model=model,
            model_provider=model_provider,
            cancel_event=cancel_event,
        )
        if cancel_event.is_set():
            publish("cancel", {"message": "Cancelled by user"})
            return
        error = str((result or {}).get("error") or "").strip()
        if error:
            logger.warning("%s turn failed", backend.get_backend_name())
            publish("error", {"message": f"{backend.get_backend_name()} request failed."})
            return
        text = str((result or {}).get("text") or "")
        if text:
            STREAM_PARTIAL_TEXT[stream_id] = text
            publish("token", {"text": text})

        if text.strip():
            session.messages.append({
                "role": "assistant",
                "content": text.strip(),
                "timestamp": int(time.time()),
            })
        session.save()
        publish("stream_end", {"text": text})
        try:
            channel.put_nowait(("done", {"session_id": session_id, "stream_id": stream_id}))
        except Exception:
            logger.debug("Could not publish adapter completion marker", exc_info=True)
    except Exception:
        logger.exception("Adapter streaming worker failed")
        publish("error", {"message": "The selected runtime request failed."})
    finally:
        try:
            from api.models import get_session

            final_session = get_session(session_id)
            if getattr(final_session, "active_stream_id", None) == stream_id:
                final_session.active_stream_id = None
                final_session.pending_user_message = None
                final_session.pending_attachments = []
                final_session.pending_started_at = None
                final_session.pending_user_source = None
                final_session.save(touch_updated_at=False)
        except Exception:
            logger.exception("Could not clear adapter stream state for %s", session_id)
        with STREAMS_LOCK:
            STREAMS.pop(stream_id, None)
            CANCEL_FLAGS.pop(stream_id, None)
            STREAM_PARTIAL_TEXT.pop(stream_id, None)
            STREAM_LAST_EVENT_ID.pop(stream_id, None)
        unregister_active_run(stream_id)
        unregister_stream_owner(stream_id)
        if journal is not None:
            try:
                journal.close()
            except Exception:
                logger.debug("Could not close adapter run journal", exc_info=True)


class AgenticBackend(ABC):
    """Abstract base for any agent backend ARES can use."""

    name: str = "unknown"
    supports_tools: bool = True
    supports_persona: bool = False

    @abstractmethod
    def is_available(self) -> bool:
        ...

    @abstractmethod
    def run_turn(self, message: str, session_id: str, **kwargs) -> Dict[str, Any]:
        ...

    def health(self) -> Dict[str, Any]:
        return {"status": "ok" if self.is_available() else "error", "latency_ms": 0.0}

    def identity_projection(self) -> Dict[str, Any]:
        return {"name": self.name, "description": "", "avatar_state": "idle"}

    def capabilities(self) -> Dict[str, Any]:
        return {"chat": True, "tools": self.supports_tools, "persona": self.supports_persona}

    def chat_session_support(self) -> Dict[str, Any]:
        return {"streaming": True, "context_window": 8192, "multimodal": False}

    def tools(self) -> List[Dict[str, Any]]:
        return []

    def presence_events(self) -> List[Dict[str, Any]]:
        return []

    def settings_schema(self) -> Dict[str, Any]:
        return {"type": "object", "properties": {}}

    def get_worker_target(self) -> tuple:
        return run_agentic_backend_streaming, False, False

    def get_status(self) -> Dict[str, Any]:
        return {"available": self.is_available(), "label": self.name}
