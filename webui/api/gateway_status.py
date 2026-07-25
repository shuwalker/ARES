"""Transport-neutral gateway status projection."""

from __future__ import annotations

import datetime
import json
import logging
import os
from pathlib import Path
import threading

from api.agent_health import build_agent_health_payload


logger = logging.getLogger(__name__)
_CACHE_LOCK = threading.Lock()
_CACHE: dict[str, object] = {"path": "", "mtime": None, "identity": {}}


def _safe_first(*values) -> str:
    for value in values:
        text = str(value or "").strip()
        if text:
            return text
    return ""


def gateway_session_metadata_path() -> Path:
    try:
        from api.profiles import get_active_ares_home

        home = Path(get_active_ares_home()).expanduser().resolve()
    except Exception:
        home = Path(os.getenv("ARES_HOME", str(Path.home() / ".ares"))).expanduser().resolve()
    return home / "sessions" / "sessions.json"


def load_gateway_session_identity_map() -> dict[str, dict]:
    path = gateway_session_metadata_path()
    if not path.exists():
        return {}
    try:
        stat = path.stat()
        with _CACHE_LOCK:
            if _CACHE["path"] == str(path) and _CACHE["mtime"] == stat.st_mtime:
                return dict(_CACHE["identity"])  # type: ignore[arg-type]
        raw_sessions = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        logger.debug("Failed to load gateway session metadata from %s: %s", path, exc)
        return {}
    mapping: dict[str, dict] = {}
    if isinstance(raw_sessions, dict):
        for entry in raw_sessions.values():
            if not isinstance(entry, dict):
                continue
            session_id = _safe_first(entry.get("session_id"))
            if not session_id:
                continue
            origin = entry.get("origin") if isinstance(entry.get("origin"), dict) else {}
            platform = _safe_first(origin.get("platform"), entry.get("platform"))
            mapping[session_id] = {
                "session_key": _safe_first(entry.get("session_key"), entry.get("key")),
                "chat_id": _safe_first(origin.get("chat_id"), entry.get("chat_id")),
                "thread_id": _safe_first(origin.get("thread_id"), entry.get("thread_id")),
                "chat_type": _safe_first(origin.get("chat_type"), entry.get("chat_type")),
                "user_id": _safe_first(origin.get("user_id"), entry.get("user_id")),
                "platform": platform,
                "raw_source": platform,
            }
    with _CACHE_LOCK:
        _CACHE.update(path=str(path), mtime=stat.st_mtime, identity=mapping)
    return mapping.copy()


def gateway_status_payload() -> dict:
    identity_map = load_gateway_session_identity_map()
    sessions_path = gateway_session_metadata_path()
    health = build_agent_health_payload()
    alive = health.get("alive")
    details = health.get("details") if isinstance(health.get("details"), dict) else {}
    health_reason = details.get("reason")
    health_state = details.get("state")
    health_gateway_state = details.get("gateway_state")
    if alive is True:
        running, configured = True, True
    elif alive is False:
        running, configured = False, True
    else:
        configured = bool(identity_map) or health_reason == "gateway_stale_running_state" or health_gateway_state == "running"
        running = bool(identity_map)
    labels = {"telegram": "Telegram", "discord": "Discord", "slack": "Slack", "email": "Email", "web": "Web", "api": "API"}
    names = {
        str(meta.get("raw_source") or meta.get("platform") or "").strip().lower()
        for meta in identity_map.values()
    }
    platforms = sorted(
        ({"name": name, "label": labels.get(name, name.title())} for name in names if name),
        key=lambda item: item["label"],
    )
    last_active = ""
    if running and sessions_path.exists():
        try:
            last_active = datetime.datetime.fromtimestamp(sessions_path.stat().st_mtime).isoformat()
        except Exception:
            pass
    return {
        "running": running,
        "configured": configured,
        "platforms": platforms,
        "last_active": last_active,
        "session_count": len(identity_map),
        "health": {"state": health_state, "reason": health_reason, "gateway_state": health_gateway_state},
    }


_load_gateway_session_identity_map = load_gateway_session_identity_map
_gateway_status_payload = gateway_status_payload

