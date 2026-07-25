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
        # ── SI Pipeline (when ARES_SI_ENABLED) ──
        from api.si.bridge import si_enabled, si_turn

        if si_enabled():
            # Honor explicit session connection when set (WebUI worker picker /
            # connection_id). Empty/unconfigured → SI router chooses.
            selected = str(getattr(session, "ares_backend", None) or "").strip()
            if selected in ("", "unconfigured", "auto", "none"):
                selected = None
            result = si_turn(
                message,
                session_id,
                target_worker=selected,
                model=model,
                model_provider=model_provider,
                cancel_event=cancel_event,
            )
        else:
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
        raw_error = (result or {}).get("error")
        if raw_error is None or raw_error is False:
            error = ""
        else:
            error = str(raw_error).strip()
            if error.lower() in ("none", "null"):
                error = ""
        if error:
            logger.warning("%s turn failed: %s", backend.get_backend_name(), error[:200])
            publish("error", {"message": f"{backend.get_backend_name()} request failed."})
            return
        raw_text = (result or {}).get("text")
        text = "" if raw_text is None else str(raw_text)
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

    def get_backend_name(self) -> str:
        """Human-readable name for legacy inventory and error surfaces."""
        return str(getattr(self, "display_label", "") or self.name)

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
<<<<<<< HEAD
        """
        Return the (callable, is_gateway, is_jros) tuple for the Hermes
        streaming worker. Subclasses override this to return their own target.
        """
        from api.streaming import _run_agent_streaming
        return _run_agent_streaming, False, False

    def get_backend_name(self) -> str:
        """Return the display name for this backend (e.g. 'Hermes', 'JROS')."""
        return self.name.title()

    def get_status(self) -> Dict[str, Any]:
        """Optional richer status for UI display."""
        return {"available": self.is_available(), "label": self.get_backend_name()}


class BackendRouter:
    """
    ARES-side router that decides which peer backend(s) to use.

    Mirrors the ExecutionBackendRouter pattern from the native macOS app.
    """

    def __init__(self, backends: Dict[str, AgenticBackend]):
        self.backends = backends

    def select(self, requested: str) -> AgenticBackend | list[AgenticBackend]:
        if requested == "hybrid":
            return [b for b in self.backends.values() if b.is_available()]
        backend = self.backends.get(requested)
        if backend and backend.is_available():
            return backend
        # Fall back to first available backend
        for name, b in self.backends.items():
            if b.is_available():
                return b
        # Absolute last resort: return the requested backend even if unavailable
        return backend or list(self.backends.values())[0]

    def select_worker(self, requested: str) -> tuple:
        """
        Return the (callable, is_gateway, is_jros) tuple for the requested
        backend. For 'hybrid' returns the first available backend's worker.
        """
        if requested == "hybrid":
            available = [b for b in self.backends.values() if b.is_available()]
            if available:
                return available[0].get_worker_target()
        
        backend = self.backends.get(requested)
        if backend:
            return backend.get_worker_target()
            
        # Fallback only if the requested backend string is completely invalid/unknown
        fallback = self.backends.get("hermes") or list(self.backends.values())[0]
        return fallback.get_worker_target()

    def get_active_backend_name(self, requested: str) -> str:
        """Return the display name for the active backend."""
        if requested == "hybrid":
            return "Hybrid"
        backend = self.backends.get(requested) or self.backends.get("hermes")
        return backend.get_backend_name() if backend else "Hermes"
=======
        return run_agentic_backend_streaming, False, False

    def get_status(self) -> Dict[str, Any]:
        return {"available": self.is_available(), "label": self.name}
>>>>>>> wip/multiagent-orchestrator
