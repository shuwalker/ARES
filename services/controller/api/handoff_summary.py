"""Deterministic, transport-neutral handoff summaries and persistence."""

from __future__ import annotations

import datetime as dt
import json
import sqlite3
import time
from contextlib import closing
from pathlib import Path


class HandoffSummaryError(RuntimeError):
    def __init__(self, status_code: int, message: str):
        super().__init__(message)
        self.status_code = status_code


def build_handoff_marker(
    session_id: str,
    summary: str,
    channel: str | None,
    rounds: int | None,
    *,
    fallback: bool,
) -> dict:
    now = time.time()
    return {
        "role": "tool",
        "tool_call_id": "",
        "name": "handoff_summary",
        "timestamp": now,
        "_ts": now,
        "content": json.dumps(
            {
                "_handoff_summary_card": True,
                "session_id": session_id,
                "summary": str(summary or "").strip(),
                "channel": str(channel or "").strip() or None,
                "rounds": rounds,
                "fallback": bool(fallback),
                "generated_at": now,
            },
            ensure_ascii=False,
        ),
    }


def _marker_payload(message: dict) -> dict | None:
    if not isinstance(message, dict) or message.get("role") != "tool" or message.get("name") != "handoff_summary":
        return None
    try:
        payload = message.get("content")
        payload = payload if isinstance(payload, dict) else json.loads(payload or "")
    except Exception:
        return None
    return payload if isinstance(payload, dict) and payload.get("_handoff_summary_card") else None


def _same_marker_content(content, expected: dict | None) -> bool:
    if expected is None:
        return False
    try:
        actual = json.loads(content or "")
    except Exception:
        return False
    keys = ("session_id", "summary", "channel", "rounds", "fallback", "_handoff_summary_card")
    return isinstance(actual, dict) and all(actual.get(key) == expected.get(key) for key in keys)


def persist_handoff_summary_to_state_db(session_id: str, marker: dict) -> bool:
    try:
        from api.profiles import get_active_ares_home

        db_path = Path(get_active_ares_home()).expanduser().resolve() / "state.db"
    except Exception:
        return False
    if not db_path.exists():
        return False
    content = marker.get("content", "")
    if not isinstance(content, str):
        content = json.dumps(content, ensure_ascii=False)
    expected = _marker_payload(marker)
    try:
        with closing(sqlite3.connect(str(db_path))) as connection:
            try:
                row = connection.execute(
                    "SELECT content FROM messages WHERE session_id = ? AND role = 'tool' ORDER BY rowid DESC LIMIT 1",
                    (session_id,),
                ).fetchone()
                if row and _same_marker_content(row[0], expected):
                    return True
            except Exception:
                pass
            connection.execute(
                "INSERT INTO messages (session_id, role, content, timestamp) VALUES (?, 'tool', ?, ?)",
                (session_id, content, marker.get("timestamp", time.time())),
            )
            try:
                connection.execute(
                    "UPDATE sessions SET message_count = COALESCE(message_count, 0) + 1 WHERE id = ?",
                    (session_id,),
                )
            except Exception:
                pass
            connection.commit()
        return True
    except Exception:
        return False


def _persist_local(session_id: str, marker: dict) -> bool:
    try:
        from api.models import get_session

        session = get_session(session_id)
    except Exception:
        return False
    try:
        current = _marker_payload(session.messages[-1]) if session.messages else None
        target = _marker_payload(marker)
        keys = ("session_id", "summary", "channel", "rounds", "fallback")
        if current and target and all(current.get(key) == target.get(key) for key in keys):
            return True
        session.messages.append(marker)
        session.save()
        return True
    except Exception:
        return False


def _text(content) -> str:
    if isinstance(content, list):
        return " ".join(
            str(part.get("text") or part.get("content") or "")
            for part in content
            if isinstance(part, dict)
        ).strip()
    return str(content or "").strip()


def _timestamp(value) -> float | None:
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return dt.datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except Exception:
        return None


def _fallback(messages: list) -> str:
    chinese = any(any("\u4e00" <= character <= "\u9fff" for character in _text(message.get("content"))) for message in messages)
    user_points: list[str] = []
    assistant_points: list[str] = []
    for message in messages:
        role = message.get("role")
        text = " ".join(_text(message.get("content")).split())
        if len(text) > 82:
            text = text[:81].rstrip() + "…"
        if role == "user" and text:
            user_points.append(text)
        elif role == "assistant" and text:
            assistant_points.append(text)
    if chinese:
        lines = []
        if user_points:
            lines.append(f"- 你刚讨论了：{user_points[-1]}。")
        if assistant_points:
            lines.append(f"- 助手已回复：{assistant_points[-1]}。")
        lines.append("- 当前对话存在尚未确认的后续动作。")
        return "\n".join(lines)
    lines = []
    if user_points:
        lines.append(f"- You asked: {user_points[-1]}.")
    if assistant_points:
        lines.append(f"- The assistant responded: {assistant_points[-1]}.")
    lines.append("- There is pending context to continue next.")
    return "\n".join(lines)


def _channel_label(session_id: str) -> str | None:
    try:
        from api.models import get_session

        session = get_session(session_id)
        return (
            session.source_label
            or session.raw_source
            or session.source_tag
            or session.session_source
        )
    except Exception:
        return None


def generate_handoff_summary(session_id: str, *, since: float | None = None) -> dict:
    from api.models import CONVERSATION_ROUND_THRESHOLD, count_conversation_rounds, get_cli_session_messages
    from api.session_access import session_is_subagent_view_only

    session_id = str(session_id or "").strip()
    if not session_id:
        raise HandoffSummaryError(400, "Missing required field(s): session_id")
    if session_is_subagent_view_only(session_id):
        raise HandoffSummaryError(400, "Subagent sessions are view-only and cannot be summarized from WebUI")
    rounds = count_conversation_rounds(session_id, since=since)
    if rounds < CONVERSATION_ROUND_THRESHOLD:
        raise HandoffSummaryError(400, "Not enough conversation rounds to generate a summary.")
    messages = get_cli_session_messages(session_id)
    if since is not None:
        messages = [message for message in messages if (_timestamp(message.get("timestamp")) or 0) > since]
    messages = messages[-50:]
    if len(messages) < 2:
        raise HandoffSummaryError(400, "Not enough messages to summarize.")
    summary = _fallback(messages)
    marker = build_handoff_marker(
        session_id,
        summary,
        _channel_label(session_id),
        rounds,
        fallback=True,
    )
    if not _persist_local(session_id, marker):
        persist_handoff_summary_to_state_db(session_id, marker)
    return {
        "ok": True,
        "summary": summary,
        "message_count": len(messages),
        "rounds": rounds,
        "fallback": True,
    }
