"""Discovery of agent session stores on this machine.

ARES imports conversation history from other agent apps. Those apps each keep
their own store in their own home directory, and until something enumerates
them the sidebar silently shows only whatever happens to be wired up — which is
how 18 Codex sessions and 10 Gemini conversations stayed invisible while the
sidebar looked complete.

This module answers one question honestly: *what agent history exists on this
computer, and how much of it can ARES currently read?* It is read-only and
never opens a write handle on another app's store.

Paths come from ``api.journal.paths`` so the env-var overrides (``CLAUDE_HOME``,
``CODEX_HOME``, ``GEMINI_HOME``, ``HERMES_HOME``) apply here too — nothing
assumes a maintainer's home layout.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any

# Import support per app. "indexed" means rows reach the sidebar today;
# "detected" means the store is found and counted but not yet parsed.
STATUS_INDEXED = "indexed"
STATUS_DETECTED = "detected"
STATUS_ABSENT = "absent"


def _safe_stat_dir(root: Path, pattern: str, *, cap: int = 5000) -> tuple[int, int]:
    """Return (file_count, total_bytes) for *pattern* under *root*, capped."""
    count = 0
    size = 0
    try:
        for path in root.rglob(pattern):
            if count >= cap:
                break
            try:
                if path.is_file():
                    count += 1
                    size += path.stat().st_size
            except (OSError, PermissionError):
                continue
    except (OSError, PermissionError):
        pass
    return count, size


def _sqlite_session_count(db_path: Path) -> int | None:
    if not db_path.exists():
        return None
    try:
        import sqlite3

        uri = f"{db_path.resolve().as_uri()}?mode=ro"
        with sqlite3.connect(uri, uri=True) as conn:
            row = conn.execute("SELECT COUNT(*) FROM sessions").fetchone()
        return int(row[0]) if row else 0
    except Exception:
        return None


def _claude_source() -> dict[str, Any]:
    from api.journal.paths import claude_projects_dir
    from api.models import CLAUDE_CODE_MAX_FILES, CLAUDE_CODE_MAX_FILE_BYTES

    root = Path(claude_projects_dir()).expanduser()
    if not root.is_dir():
        return {"status": STATUS_ABSENT, "path": str(root), "sessions": 0, "bytes": 0}

    count, size = _safe_stat_dir(root, "*.jsonl")
    oversized = 0
    try:
        for path in root.rglob("*.jsonl"):
            try:
                if path.stat().st_size > CLAUDE_CODE_MAX_FILE_BYTES:
                    oversized += 1
            except (OSError, PermissionError):
                continue
    except (OSError, PermissionError):
        pass

    # Silent truncation was the bug: more transcripts on disk than rows shown.
    skipped_by_cap = max(0, count - CLAUDE_CODE_MAX_FILES)
    notes = []
    if skipped_by_cap:
        notes.append(
            f"{skipped_by_cap} oldest transcript(s) not indexed — file cap is "
            f"{CLAUDE_CODE_MAX_FILES}"
        )
    if oversized:
        notes.append(
            f"{oversized} transcript(s) skipped for exceeding "
            f"{CLAUDE_CODE_MAX_FILE_BYTES // 1024 // 1024} MB"
        )

    return {
        "status": STATUS_INDEXED,
        "path": str(root),
        "sessions": count,
        "bytes": size,
        "indexed_sessions": max(0, min(count, CLAUDE_CODE_MAX_FILES) - oversized),
        "notes": notes,
    }


def _hermes_source() -> dict[str, Any]:
    from api.journal.paths import hermes_db

    db = Path(hermes_db()).expanduser()
    total = _sqlite_session_count(db)
    if total is None:
        return {"status": STATUS_ABSENT, "path": str(db), "sessions": 0, "bytes": 0}
    try:
        size = db.stat().st_size
    except (OSError, PermissionError):
        size = 0
    return {
        "status": STATUS_INDEXED,
        "path": str(db),
        "sessions": total,
        "bytes": size,
        "indexed_sessions": total,
        "notes": [],
    }


def _codex_source() -> dict[str, Any]:
    from api.journal.paths import codex_dir

    root = Path(codex_dir()).expanduser() / "sessions"
    if not root.is_dir():
        return {"status": STATUS_ABSENT, "path": str(root), "sessions": 0, "bytes": 0}
    count, size = _safe_stat_dir(root, "*.jsonl")
    return {
        "status": STATUS_DETECTED,
        "path": str(root),
        "sessions": count,
        "bytes": size,
        "indexed_sessions": 0,
        "notes": ["Reader not implemented — sessions are detected but not imported"],
    }


def _gemini_source() -> dict[str, Any]:
    from api.journal.paths import gemini_conversations_dir

    root = Path(gemini_conversations_dir()).expanduser()
    if not root.is_dir():
        return {"status": STATUS_ABSENT, "path": str(root), "sessions": 0, "bytes": 0}
    count = 0
    size = 0
    try:
        for entry in root.iterdir():
            count += 1
            if entry.is_file():
                try:
                    size += entry.stat().st_size
                except (OSError, PermissionError):
                    pass
    except (OSError, PermissionError):
        pass
    return {
        "status": STATUS_DETECTED,
        "path": str(root),
        "sessions": count,
        "bytes": size,
        "indexed_sessions": 0,
        "notes": ["Reader not implemented — conversations are detected but not imported"],
    }


def _jaeger_source() -> dict[str, Any]:
    """JaegerAI keeps a per-instance store under its runtime home."""
    home = os.environ.get("ARES_JAEGER_HOME") or os.environ.get("JAEGER_HOME")
    if not home:
        return {"status": STATUS_ABSENT, "path": "", "sessions": 0, "bytes": 0}

    base = Path(home).expanduser() / ".jaeger_os" / "instances"
    if not base.is_dir():
        return {"status": STATUS_ABSENT, "path": str(base), "sessions": 0, "bytes": 0}

    total = 0
    size = 0
    found_path = str(base)
    try:
        for instance in base.iterdir():
            db = instance / "memory" / "sessions.db"
            count = _sqlite_session_count(db)
            if count is None:
                continue
            found_path = str(db)
            total += count
            try:
                size += db.stat().st_size
            except (OSError, PermissionError):
                pass
    except (OSError, PermissionError):
        pass

    if not total:
        return {"status": STATUS_ABSENT, "path": found_path, "sessions": 0, "bytes": 0}
    return {
        "status": STATUS_DETECTED,
        "path": found_path,
        "sessions": total,
        "bytes": size,
        "indexed_sessions": 0,
        "notes": ["Reader not implemented — JaegerAI rows mirror gateway calls"],
    }


_SOURCES = (
    ("claude_code", "Claude Code", _claude_source),
    ("hermes", "Hermes Agent", _hermes_source),
    ("codex", "Codex", _codex_source),
    ("gemini", "Gemini / Antigravity", _gemini_source),
    ("jaeger", "JaegerAI", _jaeger_source),
)


def discover_agent_sources() -> dict[str, Any]:
    """Enumerate every known agent history store and its import status."""
    sources = []
    for source_id, label, probe in _SOURCES:
        try:
            info = probe()
        except Exception as exc:  # a broken probe must not hide the others
            info = {
                "status": STATUS_ABSENT,
                "path": "",
                "sessions": 0,
                "bytes": 0,
                "notes": [f"Probe failed: {exc}"],
            }
        info.setdefault("indexed_sessions", 0)
        info.setdefault("notes", [])
        sources.append({"id": source_id, "label": label, **info})

    return {
        "sources": sources,
        "total_sessions": sum(s["sessions"] for s in sources),
        "total_indexed": sum(s["indexed_sessions"] for s in sources),
        "unindexed": sum(
            max(0, s["sessions"] - s["indexed_sessions"])
            for s in sources
            if s["status"] != STATUS_ABSENT
        ),
    }
