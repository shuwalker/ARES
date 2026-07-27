"""Transport-neutral transcript window projection."""

from __future__ import annotations


def _renderable(message) -> bool:
    from api.models import _is_empty_partial_activity_message

    if not isinstance(message, dict) or _is_empty_partial_activity_message(message):
        return False
    role = str(message.get("role") or "").strip().lower()
    return bool(role and role != "tool")


def _tool_call_ids(messages) -> set[str]:
    result: set[str] = set()
    for message in messages or []:
        if not isinstance(message, dict):
            continue
        for key in ("tool_calls", "_partial_tool_calls"):
            for call in message.get(key) or []:
                if isinstance(call, dict) and (identifier := call.get("id") or call.get("tool_call_id")):
                    result.add(str(identifier))
        content = message.get("content")
        if isinstance(content, list):
            for part in content:
                if isinstance(part, dict) and part.get("type") == "tool_use" and part.get("id"):
                    result.add(str(part["id"]))
    return result


def _matching_tool_result(message, call_ids: set[str]) -> bool:
    if not call_ids or not isinstance(message, dict) or str(message.get("role") or "").lower() != "tool":
        return False
    identifier = message.get("tool_call_id") or message.get("tool_use_id")
    return bool(identifier) and str(identifier) in call_ids


def message_window_for_display(
    messages,
    msg_limit=None,
    msg_before=None,
    expand_renderable=False,
) -> tuple[list, int]:
    del expand_renderable
    messages = list(messages or [])
    before = len(messages) if msg_before is None else max(0, min(int(msg_before), len(messages)))
    source = messages[:before]
    if not source:
        return [], 0
    if not msg_limit:
        return source, 0
    limit = max(1, int(msg_limit))
    last = next((index for index in range(len(source) - 1, -1, -1) if _renderable(source[index])), None)
    if last is None:
        start = max(0, len(source) - limit)
        return source[start:], start
    end = last + 1
    call_ids = _tool_call_ids(source[:end])
    while end < len(source) and not _renderable(source[end]):
        if not _matching_tool_result(source[end], call_ids):
            break
        end += 1
    start = 0
    count = 0
    for index in range(last, -1, -1):
        if _renderable(source[index]):
            count += 1
            if count >= limit:
                start = index
                break
    return source[start:end], start


_message_window_for_display = message_window_for_display


__all__ = ["message_window_for_display"]
