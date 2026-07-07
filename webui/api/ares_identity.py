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
from typing import Any, Dict

logger = logging.getLogger(__name__)


def get_assistant_display_name(
    *,
    profile: str | None = None,
    bot_name: str | None = None,
    backend: str = "hermes",
) -> str:
    """Return the canonical assistant display name.

    Resolution order:
      1. If a non-default profile is active, capitalise the profile name.
      2. If the backend is 'jros', return 'JROS'.
      3. Fall back to bot_name (from settings) or 'Hermes'.
    """
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
            profile=profile, bot_name=bot_name, backend=backend
        ),
        "backend": backend,
        "backend_label": get_backend_display_name(backend),
        "backend_badge_html": get_backend_badge_html(backend),
    }
