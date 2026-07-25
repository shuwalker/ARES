"""Transport-neutral session search and export operations."""

from __future__ import annotations

import base64
import json
import re
from typing import Any


def session_search_message_text(message: Any) -> str:
    content = message.get("content") if isinstance(message, dict) else ""
    if isinstance(content, list):
        return " ".join(
            str(part.get("text", ""))
            for part in content
            if isinstance(part, dict) and part.get("type") == "text"
        )
    return str(content or "")


def session_search_preview(text: Any, query: Any, max_len: int = 124) -> str:
    normalized = re.sub(r"\s+", " ", str(text or "")).strip()
    term = re.sub(r"\s+", " ", str(query or "")).strip()
    if not normalized or not term:
        return ""
    index = normalized.lower().find(term.lower())
    if index < 0:
        return ""
    max_len = max(32, int(max_len or 124))
    if len(normalized) <= max_len:
        return normalized
    context = max(12, (max_len - len(term)) // 2)
    start = max(0, index - context)
    end = min(len(normalized), index + len(term) + context)
    if start > 0:
        while start < index and normalized[start] != " ":
            start += 1
        if start >= index:
            start = max(0, index - context)
    if end < len(normalized):
        while end > index + len(term) and normalized[end - 1] != " ":
            end -= 1
        if end <= index + len(term):
            end = min(len(normalized), index + len(term) + context)
    excerpt = normalized[start:end].strip()
    return ("..." if start else "") + excerpt + ("..." if end < len(normalized) else "")


def search_sessions(
    query: str,
    *,
    content_search: bool = True,
    depth: int = 5,
    all_profiles: bool = False,
) -> dict[str, Any]:
    from api.helpers import _redact_text
    from api.models import all_sessions, get_session
    from api.profiles import _profiles_match, get_active_profile_name

    term = str(query or "").lower().strip()
    active_profile = get_active_profile_name()
    sessions = all_sessions()
    if not all_profiles:
        sessions = [row for row in sessions if _profiles_match(row.get("profile"), active_profile)]
    depth = max(0, int(depth))
    if not term:
        safe = []
        for row in sessions:
            item = dict(row)
            if isinstance(item.get("title"), str):
                item["title"] = _redact_text(item["title"])
            safe.append(item)
        return {"sessions": safe, "all_profiles": all_profiles, "active_profile": active_profile}
    results = []
    for row in sessions:
        if term in str(row.get("title") or "").lower():
            item = dict(row, match_type="title")
        elif content_search:
            try:
                messages = get_session(row["session_id"]).messages
                messages = messages[:depth] if depth else messages
                match = next(
                    (session_search_message_text(message) for message in messages if term in session_search_message_text(message).lower()),
                    None,
                )
            except Exception:
                match = None
            if match is None:
                continue
            item = dict(row, match_type="content")
            preview = session_search_preview(match, term)
            if preview:
                item["match_preview"] = _redact_text(preview)
        else:
            continue
        if isinstance(item.get("title"), str):
            item["title"] = _redact_text(item["title"])
        results.append(item)
    return {
        "sessions": results,
        "query": term,
        "count": len(results),
        "all_profiles": all_profiles,
        "active_profile": active_profile,
    }


def export_session(
    session_id: str,
    *,
    profile: str | None,
    format: str = "json",
    theme: str = "dark",
    palette: str = "",
) -> tuple[str, str, str]:
    from api.helpers import redact_session_data
    from api.models import get_session
    from api.profiles import _profiles_match, get_active_profile_name

    try:
        session = get_session(session_id)
    except KeyError as exc:
        raise FileNotFoundError("Session not found") from exc
    active_profile = profile or get_active_profile_name()
    if not _profiles_match(getattr(session, "profile", None), active_profile):
        raise FileNotFoundError("Session not found")
    safe = redact_session_data(session.__dict__)
    if format.lower() != "html":
        return json.dumps(safe, ensure_ascii=False, indent=2), "application/json; charset=utf-8", "json"
    from api.session_export_html import render_session_html

    custom_palette = None
    if palette:
        try:
            decoded = base64.b64decode(palette, validate=False).decode("utf-8")
            candidate = json.loads(decoded)
            if isinstance(candidate, dict) and len(candidate) <= 64:
                custom_palette = candidate
        except Exception:
            pass
    return render_session_html(safe, theme=theme.lower(), palette=custom_palette), "text/html; charset=utf-8", "html"


_session_search_message_text = session_search_message_text
_session_search_preview = session_search_preview

