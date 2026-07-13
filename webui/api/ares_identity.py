"""
ARES Identity Layer — centralized source of truth for assistant display name,
backend badge rendering, and identity metadata.

This module provides a single authoritative source for:
  - assistantDisplayName: what the assistant calls itself in the UI
  - backend badge: the visual label shown next to assistant messages
  - identity metadata: structured info for the frontend identity API

Both Python (server-side rendering) and JavaScript (client-side) consume
this module. The frontend polls /api/ares/identity to stay in sync.
"""

from __future__ import annotations

import logging
import datetime
import json
from pathlib import Path
from typing import Any, Dict

import yaml

from api.paths import HOME

logger = logging.getLogger(__name__)


_DEFAULT_AI_FALLBACK = "Jarvis"


def _clean_text(value: Any) -> str:
    return str(value or "").strip()


def _profile_display_name(profile: str | None) -> str | None:
    value = _clean_text(profile)
    if value and value != "default":
        return value[0].upper() + value[1:]
    return None


def _is_default_hermes_name(value: str | None) -> bool:
    return _clean_text(value).lower() in {"", "hermes", "hermes agent", "jros"}


def _persona_display_name(persona_id: str | None) -> str | None:
    pid = _clean_text(persona_id)
    if not pid:
        return None
    try:
        from api.persona import load_persona

        persona = load_persona(pid)
    except Exception:
        logger.debug("Failed to load persona %s for identity display", pid, exc_info=True)
        persona = None
    if isinstance(persona, dict):
        identity = persona.get("identity") if isinstance(persona.get("identity"), dict) else {}
        name = _clean_text(identity.get("display_name")) or _clean_text(persona.get("name"))
        if name:
            return name
    return pid.replace("_", " ").replace("-", " ").title()


def _jros_identity_path_candidates() -> list[Path]:
    candidates: list[Path] = []
    try:
        from api.jros_paths import jaeger_home, jros_config_path, jros_instance_name

        config_path = jros_config_path()
        candidates.append(config_path.with_name("identity.yaml"))
        instance_name = jros_instance_name()
        if instance_name:
            candidates.append(jaeger_home() / ".jaeger_os" / "instances" / instance_name / "identity.yaml")
            candidates.append(Path("~/.jaeger/instances").expanduser() / instance_name / "identity.yaml")
        candidates.append(jaeger_home() / ".jaeger_os" / "instances" / "default" / "identity.yaml")
    except Exception:
        logger.debug("Failed to resolve JROS identity path candidates", exc_info=True)
    candidates.append(Path("~/.jaeger/instances/default/identity.yaml").expanduser())
    return candidates


def _jros_default_agent_name() -> str | None:
    seen: set[Path] = set()
    for path in _jros_identity_path_candidates():
        try:
            resolved = path.expanduser().resolve(strict=False)
        except OSError:
            continue
        if resolved in seen:
            continue
        seen.add(resolved)
        try:
            if not resolved.exists():
                continue
            data = yaml.safe_load(resolved.read_text(encoding="utf-8")) or {}
        except Exception:
            logger.debug("Failed to read JROS identity file %s", resolved, exc_info=True)
            continue
        if isinstance(data, dict):
            name = _clean_text(data.get("name")) or _clean_text(data.get("display_name"))
            if name:
                return name
    return None


def _default_assistant_name(bot_name: str | None) -> str:
    saved = _clean_text(bot_name)
    if saved and not _is_default_hermes_name(saved):
        return saved
    return _jros_default_agent_name() or _DEFAULT_AI_FALLBACK


def _normalize_backend(value: str | None) -> str:
    backend = _clean_text(value).lower()
    return backend if backend in {"hermes", "jros", "hybrid"} else "hermes"


def log_audit_event(session_id: str, action: str, details: str, status: str) -> None:
    """Log a safety/security event to the centralized ARES audit log.

    Saves a JSON line to ~/.ares/audit.log.
    """
    audit_dir = HOME / ".ares"
    audit_dir.mkdir(parents=True, exist_ok=True)
    audit_file = audit_dir / "audit.log"
    
    entry = {
        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "session_id": session_id,
        "action": action,
        "details": details,
        "status": status,
    }
    
    try:
        with open(audit_file, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry) + "\n")
    except Exception as exc:
        logger.warning("Failed to write to audit log: %s", exc)


def get_assistant_display_name(
    *,
    profile: str | None = None,
    bot_name: str | None = None,
    backend: str = "hermes",
    persona_id: str | None = None,
) -> str:
    """Return the canonical assistant display name.

    Resolution order:
      1. If a non-default WebUI profile is active, keep that profile label.
      2. If JROS or Hybrid is active and a character is selected, show the
         character/person being messaged.
      3. Otherwise show the user's default AI name from settings/JROS identity.
      4. Fall back to Jarvis for incomplete setup.
    """
    profile_name = _profile_display_name(profile)
    if profile_name:
        return profile_name

    normalized_backend = _normalize_backend(backend)
    if normalized_backend in {"jros", "hybrid"}:
        persona_name = _persona_display_name(persona_id)
        if persona_name:
            return persona_name

    return _default_assistant_name(bot_name)


def get_backend_badge_html(backend: str) -> str:
    """Return the HTML for a backend badge."""
    normalized_backend = _normalize_backend(backend)
    label = get_backend_display_name(normalized_backend)
    return f' <span class="msg-backend-badge" title="{label} runtime">{label}</span>'


def get_backend_display_name(backend: str) -> str:
    """Return the human-readable display name for a backend key."""
    normalized_backend = _normalize_backend(backend)
    return {"hermes": "Hermes", "jros": "JROS", "hybrid": "Hybrid"}.get(
        normalized_backend, normalized_backend.title()
    )


def build_identity_payload(
    *,
    profile: str | None = None,
    bot_name: str | None = None,
    backend: str = "hermes",
    persona_id: str | None = None,
) -> Dict[str, Any]:
    """Build the full identity payload for the /api/ares/identity endpoint.

    Returns a dict with:
      - display_name: str — what the assistant calls itself
      - backend: str — the active backend key
      - backend_label: str — human-readable backend name
      - backend_badge_html: str — HTML for the backend badge (or empty)
    """
    normalized_backend = _normalize_backend(backend)
    display_name = get_assistant_display_name(
        profile=profile, bot_name=bot_name, backend=normalized_backend, persona_id=persona_id
    )
    character_name = (
        _persona_display_name(persona_id)
        if normalized_backend in {"jros", "hybrid"} and _clean_text(persona_id)
        else None
    )
    return {
        "display_name": display_name,
        "backend": normalized_backend,
        "backend_label": get_backend_display_name(normalized_backend),
        "backend_badge_html": get_backend_badge_html(normalized_backend),
        "identity_kind": "character" if character_name else "default",
        "selected_character": _clean_text(persona_id) if character_name else "",
        "selected_character_name": character_name or "",
        "default_display_name": _default_assistant_name(bot_name),
    }
