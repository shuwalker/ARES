"""
ARES Journal — Universal path discovery.

All paths are resolved from environment variables first, then platform-appropriate
defaults. No hardcoded user directories. Works on macOS, Linux, and Windows.

Environment variables:
    ARES_HOME      — base directory for ARES data (default: ~/.ares)
    XDG_DATA_HOME  — freedesktop.org data dir (default: ~/.local/share on Linux)
    HERMES_HOME    — Hermes Agent state directory (default: ~/.hermes)
    CLAUDE_HOME    — Claude Code config directory (default: ~/.claude)
    CODEX_HOME     — Codex config directory (default: ~/.codex)
    GEMINI_HOME    — Gemini/Antigravity config directory (default: ~/.gemini)
"""

import os
import sys
from pathlib import Path


def _home() -> Path:
    """Cross-platform home directory."""
    return Path(os.environ.get("HOME") or os.environ.get("USERPROFILE") or Path.home())


def ares_home() -> Path:
    """Base ARES data directory."""
    return Path(os.environ.get("ARES_HOME", _home() / ".ares"))


def journal_dir() -> Path:
    """Journal database directory."""
    return ares_home() / "journal"


def journal_db() -> Path:
    """Journal database file."""
    return journal_dir() / "journal.db"


def hermes_db() -> Path:
    """Hermes Agent state database."""
    return Path(os.environ.get("HERMES_HOME", _home() / ".hermes")) / "state.db"


def claude_projects_dir() -> Path:
    """Claude Code projects directory."""
    return Path(os.environ.get("CLAUDE_HOME", _home() / ".claude")) / "projects"


def codex_dir() -> Path:
    """Codex config/sessions directory."""
    return Path(os.environ.get("CODEX_HOME", _home() / ".codex"))


def gemini_conversations_dir() -> Path:
    """Gemini/Antigravity conversations directory."""
    base = Path(os.environ.get("GEMINI_HOME", _home() / ".gemini"))
    return base / "antigravity-ide" / "conversations"


def gemini_state_db() -> Path:
    """Antigravity IDE state database (macOS only; None on other platforms)."""
    if sys.platform == "darwin":
        app_support = os.environ.get(
            "XDG_DATA_HOME",
            _home() / "Library" / "Application Support"
        )
        return Path(app_support) / "Antigravity IDE" / "User" / "globalStorage" / "state.vscdb"
    return None


def si_dir() -> Path:
    """Directory for SI subsystem data (plans, disclosure ledger, etc.)."""
    d = ares_home() / "si"
    d.mkdir(parents=True, exist_ok=True)
    return d


def sam_dir() -> Path | None:
    """SAM conversations directory."""
    if sys.platform == "darwin":
        app_support = os.environ.get(
            "XDG_DATA_HOME",
            _home() / "Library" / "Application Support"
        )
        return Path(app_support) / "SAM" / "conversations"
    # Linux / Windows: check XDG first, then fallback
    xdg = os.environ.get("XDG_DATA_HOME")
    if xdg:
        return Path(xdg) / "SAM" / "conversations"
    return _home() / ".local" / "share" / "SAM" / "conversations"


def imessage_db() -> Path:
    """iMessage database (macOS only)."""
    if sys.platform != "darwin":
        return None
    return Path("/Users") / os.environ.get("USER", "shared") / "Library" / "Messages" / "chat.db"


def grok_export_search_dirs() -> list[Path]:
    """Directories to search for Grok conversation exports."""
    home = _home()
    return [
        home / "Desktop",
        home / "Downloads",
        home / "Documents",
    ]


def document_scan_dirs() -> list[Path]:
    """
    Directories to scan for planning/evaluation documents.

    Scans the ARES repo docs/ folder, plus common AI brain/plan directories.
    Only includes directories that exist on this machine.
    """
    dirs: list[Path] = []

    # ARES repo docs (if available)
    ares_repo = Path(os.environ.get("ARES_REPO", ""))
    if ares_repo.is_dir():
        docs = ares_repo / "docs"
        if docs.is_dir():
            dirs.append(docs)

    # Hermes plans
    hermes_plans = Path(os.environ.get("HERMES_HOME", _home() / ".hermes")) / "plans"
    if hermes_plans.is_dir():
        dirs.append(hermes_plans)

    # Gemini brain
    gemini_brain = Path(os.environ.get("GEMINI_HOME", _home() / ".gemini")) / "antigravity-ide" / "brain"
    if gemini_brain.is_dir():
        dirs.append(gemini_brain)

    # Claude project instructions
    claude_dir = Path(os.environ.get("CLAUDE_HOME", _home() / ".claude"))
    if claude_dir.is_dir():
        dirs.append(claude_dir)

    # Codex instructions
    codex_base = Path(os.environ.get("CODEX_HOME", _home() / ".codex"))
    if codex_base.is_dir():
        dirs.append(codex_base)

    return dirs