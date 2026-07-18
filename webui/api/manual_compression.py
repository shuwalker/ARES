"""Manual session compression independent of an HTTP transport."""

from __future__ import annotations

import copy
import re
import threading
import time
from typing import Any

from api.compression_anchor import visible_messages_for_anchor


JOB_TTL_SECONDS = 600
_JOBS: dict[str, dict[str, Any]] = {}
_JOBS_LOCK = threading.Lock()


class CompressionError(RuntimeError):
    def __init__(self, status_code: int, message: str):
        super().__init__(message)
        self.status_code = status_code


def _anchor_message_key(message):
    if not isinstance(message, dict):
        return None
    role = str(message.get("role") or "")
    if not role or role == "tool":
        return None
    content = message.get("content", "")
    if isinstance(content, list):
        text = "\n".join(
            str(part.get("text") or part.get("content") or "")
            for part in content
            if isinstance(part, dict) and part.get("type") == "text"
        )
    else:
        text = str(content or "")
    normalized = " ".join(text.split()).strip()[:160]
    timestamp = message.get("_ts") or message.get("timestamp")
    attachments = message.get("attachments")
    attachment_count = len(attachments) if isinstance(attachments, list) else 0
    if not normalized and not attachment_count and not timestamp:
        return None
    return {
        "role": role,
        "ts": timestamp,
        "text": normalized,
        "attachments": attachment_count,
    }


def _estimate_tokens(messages) -> int:
    try:
        from agent.model_metadata import estimate_messages_tokens_rough

        return estimate_messages_tokens_rough(messages)
    except Exception:
        total = 0
        for message in messages or []:
            if not isinstance(message, dict):
                continue
            content = message.get("content", "")
            if isinstance(content, list):
                text = "\n".join(
                    str(part.get("text") or part.get("content") or "")
                    for part in content
                    if isinstance(part, dict)
                )
            else:
                text = str(content or "")
            total += len(text.split())
        return max(1, total)


def _summary(original, compressed, before_tokens, after_tokens, focus_topic):
    try:
        from agent.manual_compression_feedback import summarize_manual_compression

        return summarize_manual_compression(original, compressed, before_tokens, after_tokens)
    except Exception:
        headline = f"Compressed: {len(original)} → {len(compressed)} messages"
        token_line = f"Rough transcript estimate: ~{before_tokens} → ~{after_tokens} tokens"
        note = f"Focus: {focus_topic}" if focus_topic else None
        return {
            "headline": headline,
            "token_line": token_line,
            "note": note,
            "reference_message": (
                f"[CONTEXT COMPACTION — REFERENCE ONLY] {headline}\n{token_line}\n"
                + (f"{note}\n" if note else "")
                + "Compression completed."
            ),
        }


def _summary_text(summary, compressed):
    if isinstance(summary, dict):
        value = summary.get("reference_message") or summary.get("token_line") or summary.get("headline")
        if value:
            return re.sub(r"\s+", " ", str(value).strip())
    for message in reversed(compressed or []):
        if not isinstance(message, dict) or str(message.get("role") or "").lower() != "assistant":
            continue
        content = message.get("content")
        if isinstance(content, str) and "context comp" in content.lower():
            return re.sub(r"\s+", " ", content.strip())
    return None


def compress_session(session_id: str, *, focus_topic: str | None = None) -> dict:
    from api.config import _get_session_agent_lock, _resolve_cli_toolsets
    import api.config as config
    from api.helpers import redact_session_data
    from api.models import get_session
    from api.oauth import resolve_runtime_provider_with_anthropic_env_lock
    from api.session_access import session_is_subagent_view_only
    from api.session_ops import _truncation_watermark_for
    from api.streaming import _compact_summary_text, _sanitize_messages_for_api, _stamp_missing_message_timestamps

    session_id = str(session_id or "").strip()
    if not session_id:
        raise CompressionError(400, "Missing required field(s): session_id")
    if session_is_subagent_view_only(session_id):
        raise CompressionError(400, "Subagent sessions are view-only and cannot be compressed from WebUI")
    focus_topic = str(focus_topic or "").strip()[:500] or None
    try:
        session = get_session(session_id)
    except KeyError as exc:
        raise CompressionError(404, "Session not found") from exc
    if getattr(session, "active_stream_id", None):
        raise CompressionError(409, "Session is still streaming; wait for the current turn to finish.")
    messages = _sanitize_messages_for_api(session.messages)
    if len(messages) < 4:
        raise CompressionError(400, "Not enough conversation to compress (need at least 4 messages).")

    model, provider, base_url = config.resolve_model_provider(
        config.model_with_provider_context(session.model, getattr(session, "model_provider", None))
    )
    api_key = None
    try:
        import ares_cli.runtime_provider as runtime_provider

        runtime = resolve_runtime_provider_with_anthropic_env_lock(
            runtime_provider.resolve_runtime_provider,
            requested=provider,
        )
        api_key = runtime.get("api_key")
        provider = provider or runtime.get("provider")
        base_url = base_url or runtime.get("base_url")
    except Exception:
        pass
    if isinstance(provider, str) and provider.startswith("custom:"):
        custom_key, custom_url = config.resolve_custom_provider_connection(provider)
        api_key = api_key or custom_key
        base_url = base_url or custom_url
    if not api_key:
        raise CompressionError(400, "No provider configured -- cannot compress.")

    original = list(messages)
    stream_state = (
        getattr(session, "active_stream_id", None),
        getattr(session, "pending_user_message", None),
        copy.deepcopy(getattr(session, "pending_attachments", None)),
        getattr(session, "pending_started_at", None),
    )
    before_tokens = _estimate_tokens(original)
    try:
        import run_agent

        agent = run_agent.AIAgent(
            model=model,
            provider=provider,
            base_url=base_url,
            api_key=api_key,
            platform="webui",
            quiet_mode=True,
            enabled_toolsets=_resolve_cli_toolsets(),
            session_id=session_id,
        )
        compressed = agent.context_compressor.compress(
            original,
            current_tokens=before_tokens,
            focus_topic=focus_topic,
        )
    except CompressionError:
        raise
    except Exception as exc:
        from api.helpers import _sanitize_error

        raise CompressionError(400, f"Compression failed: {_sanitize_error(exc)}") from exc
    after_tokens = _estimate_tokens(compressed)
    summary = _summary(original, compressed, before_tokens, after_tokens, focus_topic)

    with _get_session_agent_lock(session_id):
        current_stream_state = (
            getattr(session, "active_stream_id", None),
            getattr(session, "pending_user_message", None),
            copy.deepcopy(getattr(session, "pending_attachments", None)),
            getattr(session, "pending_started_at", None),
        )
        if current_stream_state != stream_state:
            raise CompressionError(409, "Session stream state changed during compression; please retry.")
        if _sanitize_messages_for_api(session.messages) != original:
            raise CompressionError(409, "Session was modified during compression; please retry.")
        compressed_copy = copy.deepcopy(compressed)
        _stamp_missing_message_timestamps(compressed_copy)
        session.context_messages = compressed_copy
        session.active_stream_id = None
        session.pending_user_message = None
        session.pending_attachments = []
        session.pending_started_at = None
        session.pending_user_source = None
        visible = visible_messages_for_anchor(session.messages, auto_compression=False)
        session.compression_anchor_visible_idx = max(0, len(visible) - 1) if visible else None
        session.compression_anchor_message_key = _anchor_message_key(visible[-1]) if visible else None
        session.compression_anchor_summary = _compact_summary_text(_summary_text(summary, compressed))
        watermark = _truncation_watermark_for(compressed_copy)
        session.truncation_watermark = watermark
        session.truncation_boundary = watermark
        session.compression_anchor_mode = "manual"
        session.last_prompt_tokens = after_tokens
        session.save()
        try:
            session.path.with_suffix(".json.bak").unlink(missing_ok=True)
        except OSError:
            pass
    payload = redact_session_data(
        session.compact()
        | {
            "messages": session.messages,
            "tool_calls": session.tool_calls,
            "active_stream_id": session.active_stream_id,
            "pending_user_message": session.pending_user_message,
            "pending_attachments": session.pending_attachments,
            "pending_started_at": session.pending_started_at,
            "compression_anchor_visible_idx": session.compression_anchor_visible_idx,
            "compression_anchor_message_key": session.compression_anchor_message_key,
        }
    )
    return {"ok": True, "session": payload, "summary": summary, "focus_topic": focus_topic}


def _cleanup_jobs(now: float | None = None) -> None:
    now = time.time() if now is None else now
    for session_id, job in list(_JOBS.items()):
        if job.get("status") != "running" and now - float(job.get("updated_at") or now) > JOB_TTL_SECONDS:
            _JOBS.pop(session_id, None)


def compression_status(session_id: str) -> dict:
    session_id = str(session_id or "").strip()
    if not session_id:
        raise CompressionError(400, "session_id is required")
    with _JOBS_LOCK:
        _cleanup_jobs()
        job = copy.deepcopy(_JOBS.get(session_id))
    if not job:
        return {"ok": True, "status": "idle", "session_id": session_id}
    status = job.get("status", "running")
    payload = {
        "ok": status not in {"error", "cancelled"},
        "status": status,
        "session_id": session_id,
        "focus_topic": job.get("focus_topic"),
        "started_at": job.get("started_at"),
        "updated_at": job.get("updated_at"),
    }
    if status == "done":
        payload.update(job.get("result") or {})
        payload.update(ok=True, status="done")
    elif status in {"error", "cancelled"}:
        payload.update(
            ok=False,
            error=job.get("error") or "Compression failed",
            error_status=int(job.get("error_status") or 400),
        )
    return payload


def _compression_worker(session_id: str, focus_topic: str | None):
    try:
        from api.models import get_session
        from api.profiles import profile_env_for_background_worker

        session = get_session(session_id)
        with profile_env_for_background_worker(session, "manual compression"):
            result = compress_session(session_id, focus_topic=focus_topic)
        update = {"status": "done", "result": result, "updated_at": time.time()}
    except CompressionError as exc:
        update = {
            "status": "error",
            "error": str(exc),
            "error_status": exc.status_code,
            "updated_at": time.time(),
        }
    except Exception as exc:
        from api.helpers import _sanitize_error

        update = {
            "status": "error",
            "error": f"Compression failed: {_sanitize_error(exc)}",
            "error_status": 500,
            "updated_at": time.time(),
        }
    with _JOBS_LOCK:
        if session_id in _JOBS:
            _JOBS[session_id].update(update)


def start_compression(session_id: str, *, focus_topic: str | None = None) -> dict:
    from api.models import get_session

    session_id = str(session_id or "").strip()
    if not session_id:
        raise CompressionError(400, "session_id is required")
    try:
        session = get_session(session_id)
    except KeyError as exc:
        raise CompressionError(404, "Session not found") from exc
    if getattr(session, "active_stream_id", None):
        raise CompressionError(409, "Session is still streaming; wait for the current turn to finish.")
    focus_topic = str(focus_topic or "").strip()[:500] or None
    now = time.time()
    with _JOBS_LOCK:
        _cleanup_jobs(now)
        existing = _JOBS.get(session_id)
        if existing and existing.get("status") == "running":
            return compression_status_unlocked(existing)
        _JOBS[session_id] = {
            "session_id": session_id,
            "focus_topic": focus_topic,
            "status": "running",
            "started_at": now,
            "updated_at": now,
        }
        payload = compression_status_unlocked(_JOBS[session_id])
    threading.Thread(
        target=_compression_worker,
        args=(session_id, focus_topic),
        name=f"manual-compress-{session_id[:8]}",
        daemon=True,
    ).start()
    return payload


def compression_status_unlocked(job: dict) -> dict:
    return {
        "ok": True,
        "status": "running",
        "session_id": job.get("session_id"),
        "focus_topic": job.get("focus_topic"),
        "started_at": job.get("started_at"),
        "updated_at": job.get("updated_at"),
    }
