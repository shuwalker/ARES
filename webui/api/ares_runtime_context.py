"""ARES Runtime Context — builds live operating state every turn.

ARES projects the active backend's identity. This module produces a compact context
packet that gets injected into the agent's system prompt every turn,
regardless of which backend (Hermes or JROS) is active.

The context tells the agent:
  - Who it is (projected backend identity)
  - Which backend is running
  - What capabilities are available
  - What open promises/tasks exist
  - Whether JROS embodiment is connected

This is backend-agnostic — the same dict and prompt render work for
both Hermes (injected via ephemeral_system_prompt) and JROS (injected
via JaegerAgent system_prompt).
"""

from __future__ import annotations

import logging
import os
import sqlite3
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

# Lazy import — avoids circular dependency at module level.
# backend_selector.is_jros_available() is the canonical probe.
_IS_JROS_AVAILABLE_FUNC: Optional[Any] = None


def _get_jros_available_func():
    """Lazy-load the JROS availability check from backend_selector."""
    global _IS_JROS_AVAILABLE_FUNC
    if _IS_JROS_AVAILABLE_FUNC is not None:
        return _IS_JROS_AVAILABLE_FUNC
    try:
        from api.backend_selector import is_jros_available
        _IS_JROS_AVAILABLE_FUNC = is_jros_available
    except ImportError:
        logging.getLogger(__name__).debug(
            "backend_selector not available — JROS assumed down"
        )
        _IS_JROS_AVAILABLE_FUNC = lambda: False
    return _IS_JROS_AVAILABLE_FUNC


def is_jros_available() -> bool:
    """Check if JROS daemon is reachable. Delegates to backend_selector."""
    func = _get_jros_available_func()
    try:
        return bool(func())
    except Exception:
        return False


# ── ARES Continuity DB ────────────────────────────────────────────

_ARES_DB_DIR = Path(os.environ.get("ARES_HOME", os.path.expanduser("~/.ares")))
_ARES_DB_PATH = _ARES_DB_DIR / "ares_continuity.db"


def _ensure_db() -> sqlite3.Connection:
    """Create or open the ARES continuity database."""
    _ARES_DB_DIR.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(_ARES_DB_PATH))
    conn.row_factory = sqlite3.Row
    conn.execute("""
        CREATE TABLE IF NOT EXISTS tasks (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            description TEXT DEFAULT '',
            priority TEXT DEFAULT 'medium',
            status TEXT DEFAULT 'open',
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS promises (
            id TEXT PRIMARY KEY,
            text TEXT NOT NULL,
            source TEXT DEFAULT '',
            captured_at TEXT NOT NULL,
            resolved TEXT DEFAULT 0
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS audit_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            turn_id TEXT NOT NULL,
            status TEXT NOT NULL,
            checks TEXT DEFAULT '{}',
            timestamp TEXT NOT NULL
        )
    """)
    conn.commit()
    return conn


# ── Build Runtime Context ─────────────────────────────────────────

def build_runtime_context(
    backend: str = "hermes",
    *,
    session_id: Optional[str] = None,
) -> dict[str, Any]:
    """Build the ARES runtime context packet.

    This is injected into the agent's system prompt every turn so
    the agent knows the projected identity, backend, and available capabilities.

    Args:
        backend: Active backend mode — 'hermes', 'jros', or 'hybrid'.
        session_id: Optional session identifier.

    Returns:
        Dict with ARES operating state.
    """
    try:
        from api.ares_self_persistence import should_inject_self_persistence
    except ImportError:
        # Fallback: self-persistence is opt-in
        def should_inject_self_persistence(config):
            return True

    jros_up = is_jros_available()

    # Determine effective backend
    effective_backend = backend
    if backend == "jros" and not jros_up:
        effective_backend = "hermes"
    elif backend == "hybrid" and not jros_up:
        effective_backend = "hermes"

    # Capability map — what each backend provides
    capabilities = {
        "hermes": {
            "available": True,
            "provides": [
                "tools", "skills", "cron", "memory",
                "delegation", "terminal", "web_search",
                "browser", "file_ops",
            ],
        },
        "jros": {
            "available": jros_up,
            "provides": [
                "embodiment", "speech", "hearing", "vision",
                "motor_control", "animation", "skill_tree",
                "timeline",
            ] if jros_up else [],
        },
        "ares": {
            "available": True,
            "provides": [
                "identity_projection", "tasks", "self_audit",
                "followthrough", "continuity",
            ],
        },
    }

    # Load open tasks from continuity DB
    open_tasks: list[dict[str, str]] = []
    try:
        conn = _ensure_db()
        rows = conn.execute(
            "SELECT id, title, status, priority FROM tasks "
            "WHERE status != 'done' ORDER BY priority DESC, created_at ASC "
            "LIMIT 10"
        ).fetchall()
        open_tasks = [
            {"id": r["id"], "title": r["title"],
             "status": r["status"], "priority": r["priority"]}
            for r in rows
        ]
        conn.close()
    except Exception:
        pass  # DB not ready — empty tasks is fine

    # Load unresolved promises
    open_promises: list[dict[str, str]] = []
    try:
        conn = _ensure_db()
        rows = conn.execute(
            "SELECT id, text FROM promises WHERE resolved = 0 "
            "ORDER BY captured_at DESC LIMIT 5"
        ).fetchall()
        open_promises = [
            {"id": r["id"], "text": r["text"]} for r in rows
        ]
        conn.close()
    except Exception:
        pass

    device_summary: dict[str, Any] = {}
    try:
        from api.ares_devices import device_status
        from api.config import get_config

        status = device_status(get_config())
        device = status.get("device") if isinstance(status, dict) else {}
        device_summary = {
            "ai_id": status.get("ai_id", ""),
            "role": status.get("role", ""),
            "is_primary": bool(status.get("is_primary")),
            "device_id": device.get("device_id", "") if isinstance(device, dict) else "",
            "device_name": device.get("device_name", "") if isinstance(device, dict) else "",
            "primary": status.get("primary", {}),
        }
    except Exception:
        device_summary = {}

    context: dict[str, Any] = {
        "identity_projection": _identity_projection_for_backend(effective_backend),
        "active_backend": effective_backend,
        "session_id": session_id or "",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "capabilities": capabilities,
        "open_tasks": open_tasks,
        "open_promises": open_promises,
        "self_persistence_enabled": should_inject_self_persistence({}),
        "embodiment": {
            "body": "desktop" if not jros_up else "droid",
            "jros_connected": jros_up,
        },
        "device": device_summary,
    }

    return context


# ── Render for Prompt Injection ───────────────────────────────────

def render_context_prompt(context: dict[str, Any]) -> str:
    """Render the runtime context into a compact system prompt block.

    This is injected above persona/backend-specific prompts so ARES
    operating state is visible without claiming canonical persona ownership.

    Designed to be under 500 chars to minimize context window impact.
    """
    backend = context.get("active_backend", "hermes")
    identity = context.get("identity_projection", {})
    if not isinstance(identity, dict):
        identity = {}
    identity_name = str(identity.get("name") or backend.title())
    jros_up = context.get("capabilities", {}).get("jros", {}).get("available", False)
    lines = [
        f"Projected identity: {identity_name}. Backend: {backend}.",
    ]

    if jros_up:
        lines.append("JROS embodiment connected: speech, hearing, vision, motor control available.")
    else:
        lines.append("No JROS embodiment — desktop mode.")

    device = context.get("device") or {}
    if isinstance(device, dict) and device.get("role"):
        role = "primary AI body" if device.get("is_primary") else "joined ARES device"
        lines.append(f"ARES device: {device.get('device_id') or 'unknown'} ({role}).")

    # Compact task count
    tasks = context.get("open_tasks", [])
    if tasks:
        lines.append(f"Open tasks: {len(tasks)}.")

    promises = context.get("open_promises", [])
    if promises:
        lines.append(f"Unresolved promises: {len(promises)}.")

    return "\n".join(lines)


def _identity_projection_for_backend(backend: str) -> dict[str, Any]:
    """Return the active backend identity projection without making ARES canonical."""

    normalized = backend if backend in {"hermes", "jros", "hybrid"} else "hermes"
    try:
        from api.backends.router import get_router

        selected = get_router().backends.get(normalized)
        if selected is not None:
            projection = selected.identity_projection()
            if isinstance(projection, dict):
                return projection
    except Exception:
        pass

    return {
        "name": {
            "hermes": "Hermes",
            "jros": "JROS",
            "hybrid": "Hybrid",
        }.get(normalized, normalized.title()),
        "description": "Fallback identity projection",
        "avatar_state": "idle",
    }
