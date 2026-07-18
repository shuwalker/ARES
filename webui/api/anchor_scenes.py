"""Bounded persistence for assistant-message activity scenes."""

from __future__ import annotations

import copy
import hashlib
import json
import re
import time


MAX_SCENE_BYTES = 256_000
MAX_SCENE_ROWS = 1_000
MAX_SCENES_PER_SESSION = 256


class AnchorSceneError(RuntimeError):
    def __init__(self, status_code: int, message: str):
        super().__init__(message)
        self.status_code = status_code


def sanitize_scene(scene) -> dict:
    if not isinstance(scene, dict):
        raise AnchorSceneError(400, "scene must be an object")
    if str(scene.get("version") or "") != "activity_scene_v1":
        raise AnchorSceneError(400, "scene.version must be activity_scene_v1")
    rows = scene.get("activity_rows")
    if not isinstance(rows, list):
        raise AnchorSceneError(400, "scene.activity_rows must be a list")
    if len(rows) > MAX_SCENE_ROWS:
        raise AnchorSceneError(400, "scene.activity_rows is too large")
    encoded = json.dumps(copy.deepcopy(scene), ensure_ascii=False, separators=(",", ":"), default=str).encode()
    if len(encoded) > MAX_SCENE_BYTES:
        raise AnchorSceneError(400, "scene payload is too large")
    return json.loads(encoded)


def message_ref_payload(message: dict) -> dict:
    content = message.get("content")
    if isinstance(content, list):
        text = "\n".join(
            str(part.get("text") or part.get("content") or part.get("input_text") or "")
            if isinstance(part, dict)
            else str(part or "")
            for part in content
        )
    else:
        text = str(content or "")
    return {
        "role": str(message.get("role") or ""),
        "content": " ".join(text.split()),
        "timestamp": message.get("_ts") or message.get("timestamp") or "",
    }


def message_ref(message: dict) -> str:
    raw = json.dumps(message_ref_payload(message), ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode()).hexdigest()


def normalize_message_ref(reference) -> str:
    value = str(reference or "").strip()
    if not value:
        return ""
    if re.fullmatch(r"[0-9a-fA-F]{64}", value):
        return value.lower()
    try:
        payload = json.loads(value)
    except (TypeError, ValueError):
        return value
    if not isinstance(payload, dict):
        return value
    canonical = {
        "role": str(payload.get("role") or ""),
        "content": " ".join(str(payload.get("content") or "").split()),
        "timestamp": payload.get("timestamp") or "",
    }
    raw = json.dumps(canonical, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(raw.encode()).hexdigest()


def _requested_index(message_index, message_offset, message_window_index) -> int | None:
    def integer(value):
        try:
            return int(value)
        except (TypeError, ValueError):
            return None

    index = integer(message_index)
    offset = integer(message_offset)
    window_index = integer(message_window_index)
    if window_index is not None and offset is not None and offset > 0 and (index is None or index == window_index):
        return window_index + offset
    return index


def _find_message(messages: list, *, index: int | None, reference: str):
    normalized_ref = normalize_message_ref(reference)
    if normalized_ref:
        matches = [
            (candidate_index, message)
            for candidate_index, message in enumerate(messages)
            if isinstance(message, dict)
            and message.get("role") == "assistant"
            and message_ref(message) == normalized_ref
        ]
        if len(matches) == 1:
            return matches[0]
        if len(matches) != 0:
            return None, None
    if index is not None and 0 <= index < len(messages):
        candidate = messages[index]
        if isinstance(candidate, dict) and candidate.get("role") == "assistant":
            return index, candidate
    if normalized_ref:
        return None, None
    for candidate_index in range(len(messages) - 1, -1, -1):
        candidate = messages[candidate_index]
        if isinstance(candidate, dict) and candidate.get("role") == "assistant":
            return candidate_index, candidate
    return None, None


def persist_anchor_scene(
    session_id: str,
    scene,
    *,
    active_profile: str | None,
    message_index=None,
    message_offset=None,
    message_window_index=None,
    message_reference: str = "",
    stream_id: str = "",
) -> dict:
    from api.config import _get_session_agent_lock
    from api.profiles import _profiles_match
    from api.session_access import get_or_materialize_session

    session_id = str(session_id or "").strip()
    if not session_id:
        raise AnchorSceneError(400, "Missing required field(s): session_id")
    scene = sanitize_scene(scene)
    try:
        session = get_or_materialize_session(session_id)
    except KeyError as exc:
        raise AnchorSceneError(404, "Session not found") from exc
    except PermissionError as exc:
        raise AnchorSceneError(403, "Read-only imported sessions cannot persist anchor scenes") from exc
    if not _profiles_match(getattr(session, "profile", None), active_profile or "default"):
        raise AnchorSceneError(404, "Session not found")
    index = _requested_index(message_index, message_offset, message_window_index)
    with _get_session_agent_lock(session_id):
        index, message = _find_message(
            list(getattr(session, "messages", None) or []),
            index=index,
            reference=message_reference,
        )
        if index is None or message is None:
            raise AnchorSceneError(404, "Assistant message not found")
        if scene.get("turn_duration") is None:
            for key in ("_turnDuration", "_turn_duration", "turn_duration"):
                duration = message.get(key)
                if isinstance(duration, (int, float)) and duration >= 0:
                    scene["turn_duration"] = duration
                    break
        reference = message_ref(message)
        records = getattr(session, "anchor_activity_scenes", None)
        records = dict(records) if isinstance(records, dict) else {}
        records[reference or f"index:{index}"] = {
            "version": "anchor_activity_scene_record_v1",
            "message_index": index,
            "message_ref": reference,
            "stream_id": str(stream_id or ""),
            "scene": scene,
            "updated_at": time.time(),
        }
        if len(records) > MAX_SCENES_PER_SESSION:
            records = dict(
                sorted(records.items(), key=lambda item: float((item[1] or {}).get("updated_at") or 0))[
                    -MAX_SCENES_PER_SESSION:
                ]
            )
        session.anchor_activity_scenes = records
        session.save(touch_updated_at=False, skip_index=True)
    return {"ok": True, "message_index": index, "message_ref": reference}
