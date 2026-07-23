"""ARES Backend Adapter Base — defines the contract for any agent backend.

Pure ARES code. Backends are never modified — ARES wraps them.
Each backend is just {name}_{deployment}. No roles, no opinions.

Streaming contract:
  Backends that support real-time streaming receive a ``publish`` callable
  in ``run_turn(**kwargs)``. They call ``publish("token", {"text": chunk})``
  for each token as it arrives. The bridge in ``run_agentic_backend_streaming``
  detects streaming by checking if the backend used the publish callback.
  If the backend did NOT stream (legacy subprocess backends), the bridge
  publishes the full text as a single token event.
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
    """Bridge synchronous adapter turns into the canonical stream contract.

    Passes a ``publish`` callback to ``backend.run_turn()``. SDK-based
    backends (OpenAI, Anthropic, Gemini, Hermes proxy) stream tokens in
    real-time through this callback. Legacy subprocess backends return the
    full text at once — the bridge detects this and publishes it as a
    single token event.

    The ``publish`` callback is only passed when the backend's
    ``get_worker_target()`` indicates it supports streaming (first element
    of the tuple is this function itself).
    """

    del workspace, goal_related
    # attachments are passed through to the backend via run_turn kwargs
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

    # Track whether the backend streamed tokens via the publish callback
    _streamed = threading.Event()

    def publish(event: str, data: dict) -> None:
        if event == "token":
            _streamed.set()
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
        # ── LangGraph-style history injection ──────────────────────────
        # The orchestrator (ARES) owns the conversation history, not the
        # backend. Every backend receives the full message context so that
        # switching backends between turns preserves continuity.
        # This mirrors LangGraph's add_messages reducer pattern.
        from api.conversation_history import build_context_prompt

        context_prompt = build_context_prompt(
            message,
            existing,
            current_backend_id=getattr(backend, "name", None),
        )
        # ──────────────────────────────────────────────────────────────
        # Chat / agentic streaming is a pure worker path. Do not inject Companion
        # SI identity prompts here — that belongs on the Companion surface.
        # (ARES_SI_ENABLED still exists for future Companion orchestration.)
        result = backend.run_turn(
            context_prompt,
            session_id,
            model=model,
            model_provider=model_provider,
            cancel_event=cancel_event,
            publish=publish,  # Pass publish callback for real-time streaming
            attachments=attachments,  # Pass file attachments to the backend
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

        # Only publish the full text if the backend did NOT stream it
        # token-by-token. SDK backends (OpenAI, Anthropic, Gemini, Hermes
        # proxy) stream via the publish callback — the bridge must not
        # double-publish.
        if text and not _streamed.is_set():
            STREAM_PARTIAL_TEXT[stream_id] = text
            publish("token", {"text": text})

        if text.strip():
            session.messages.append({
                "role": "assistant",
                "content": text.strip(),
                "timestamp": int(time.time()),
                "backend_id": getattr(backend, "name", None),
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
        return run_agentic_backend_streaming, False, False

    def get_status(self) -> Dict[str, Any]:
        return {"available": self.is_available(), "label": self.name}

    def inventory(self) -> Dict[str, Any]:
        """Full capability catalog for System / SI routing.

        Declares models (local and cloud), transports, gateways, and MCP tools
        even when ARES is not using every path today. Subclasses should override
        with framework-specific discovery; the default is a minimal shell.
        """
        from api.backends.catalog import empty_inventory, finalize_inventory, transport_entry

        base = empty_inventory(worker_id=self.name, display_name=self.get_backend_name())
        base["transports"] = [
            transport_entry(
                id="default",
                kind="other",
                label="Default adapter path",
                in_use=True,
                notes="Subclass should replace with real transports.",
            )
        ]
        base["tools_summary"] = list(self.tools() or [])
        base["active_execution"] = {
            "available": self.is_available(),
            "capabilities": self.capabilities(),
        }
        return finalize_inventory(base)
