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

from api.paths import HOME

logger = logging.getLogger(__name__)


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
      1. If JROS backend or Hybrid mode is active, query JROS instance or configuration
         to project its active persona display name.
      2. If a non-default profile is active, capitalise the profile name.
      3. If the backend is 'jros', return 'JROS'.
      4. Fall back to bot_name (from settings) or 'Hermes'.
    """
    if backend == "jros":
        from api.jros_paths import jros_instance_name
        active_persona = jros_instance_name()
        if active_persona:
            from api.persona import load_persona
            persona = load_persona(active_persona)
            if persona:
                name = persona.get("identity", {}).get("display_name") or persona.get("name")
                if name:
                    return name
            return active_persona.title()
    elif backend == "hybrid" or persona_id:
        pid = persona_id
        if not pid:
            from api.config import get_config
            pid = get_config().get("ares_persona")
        if pid:
            from api.persona import load_persona
            persona = load_persona(pid)
            if persona:
                name = persona.get("identity", {}).get("display_name") or persona.get("name")
                if name:
                    return name
            return pid.title()

    if profile and profile != "default":
        return profile[0].upper() + profile[1:] if profile else "Hermes"
    if backend == "jros":
        return "JROS"
    return bot_name or "Hermes"


def get_backend_badge_html(backend: str) -> str:
    """Return the HTML for a backend badge, or empty string if none needed.

    Currently only JROS gets a badge. Hermes and Hybrid are unbadged.
    """
    if backend == "jros":
        return ' <span class="msg-backend-badge" title="JROS backend">JROS</span>'
    return ""


def get_backend_display_name(backend: str) -> str:
    """Return the human-readable display name for a backend key."""
    return {"hermes": "Hermes", "jros": "JROS", "hybrid": "Hybrid"}.get(
        backend, backend.title()
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
    return {
        "display_name": get_assistant_display_name(
            profile=profile, bot_name=bot_name, backend=backend, persona_id=persona_id
        ),
        "backend": backend,
        "backend_label": get_backend_display_name(backend),
        "backend_badge_html": get_backend_badge_html(backend),
    }
