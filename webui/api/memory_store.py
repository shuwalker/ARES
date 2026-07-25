"""Local Profile memory and project-context persistence.

The active runtime remains the authority for runtime memory. This module owns
only the ARES Local Profile files exposed by the Memory settings surface.
"""

from __future__ import annotations

import errno
import logging
import os
from pathlib import Path
from typing import Any

from api.helpers import _redact_text

logger = logging.getLogger(__name__)


PROJECT_CONTEXT_ARES_NAMES = (".ares.md", "ARES.md")
PROJECT_CONTEXT_CWD_NAMES = (
    "AGENTS.md",
    "agents.md",
    "CLAUDE.md",
    "claude.md",
    ".cursorrules",
)
PROJECT_CONTEXT_CURSOR_RULES_GLOB = ".cursor/rules/*.mdc"
PROJECT_CONTEXT_MAX_BYTES = 20_000


class MemoryStoreError(ValueError):
    def __init__(self, message: str, status_code: int = 400) -> None:
        super().__init__(message)
        self.status_code = status_code


def _active_home() -> Path:
    try:
        from api.profiles import get_active_ares_home

        return Path(get_active_ares_home()).expanduser()
    except ImportError:
        return Path.home() / ".ares"


def strip_project_context_frontmatter(content: str) -> str:
    if not content.startswith("---"):
        return content
    lines = content.splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        return content
    for index in range(1, len(lines)):
        if lines[index].strip() in ("---", "..."):
            return "".join(lines[index + 1 :]).lstrip("\n")
    return content


def project_context_git_root(start: Path) -> Path | None:
    current = start.resolve()
    for parent in [current, *current.parents]:
        if (parent / ".git").exists():
            return parent
    return None


def project_context_candidates(workspace: Path) -> list[Path]:
    """Return candidates without walking above a non-git workspace."""

    current = workspace.resolve()
    candidates: list[Path] = []
    git_root = project_context_git_root(current)
    stop_at = git_root if git_root is not None else current

    for directory in [current, *current.parents]:
        candidates.extend(directory / name for name in PROJECT_CONTEXT_ARES_NAMES)
        if directory == stop_at:
            break
    candidates.extend(current / name for name in PROJECT_CONTEXT_CWD_NAMES)
    try:
        candidates.extend(sorted(current.glob(PROJECT_CONTEXT_CURSOR_RULES_GLOB)))
    except OSError:
        pass
    return candidates


def read_active_project_context(workspace: Path | None) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "content": "",
        "path": "",
        "mtime": None,
        "workspace": str(workspace) if workspace else "",
        "shadowed": [],
    }
    if not workspace:
        return payload
    try:
        if not workspace.exists() or not workspace.is_dir():
            return payload
    except OSError:
        return payload

    seen: set[str] = set()
    readable: list[dict[str, Any]] = []
    for candidate in project_context_candidates(workspace):
        try:
            if not candidate.is_file():
                continue
            resolved = candidate.resolve()
            key = os.path.normcase(str(resolved)).casefold()
            if key in seen:
                continue
            seen.add(key)
            content = strip_project_context_frontmatter(
                resolved.read_text(encoding="utf-8", errors="replace")
            )[:PROJECT_CONTEXT_MAX_BYTES]
            if not content.strip():
                continue
            readable.append(
                {
                    "name": resolved.name,
                    "path": str(resolved),
                    "content": content,
                    "mtime": resolved.stat().st_mtime,
                }
            )
        except Exception:
            continue

    if not readable:
        return payload
    active = readable[0]
    payload.update(
        {
            "content": active["content"],
            "path": active["path"],
            "mtime": active["mtime"],
            "name": active["name"],
            "shadowed": [
                {
                    "name": item["name"],
                    "path": item["path"],
                    "mtime": item["mtime"],
                    "shadowed_by": active["name"],
                    "shadowed_by_path": active["path"],
                }
                for item in readable[1:]
            ],
        }
    )
    return payload


def resolve_project_context_workspace(
    *, session_id: str = "", workspace: str = ""
) -> Path | None:
    if session_id:
        try:
            from api.models import get_session

            value = str(get_session(session_id).workspace or "").strip()
            return Path(value).expanduser().resolve() if value else None
        except Exception:
            return None

    if not workspace:
        from api.models import get_last_workspace

        workspace = os.environ.get("TERMINAL_CWD", "") or get_last_workspace()
    if not workspace:
        return None
    try:
        from api.workspace import resolve_trusted_workspace

        return Path(resolve_trusted_workspace(workspace)).expanduser().resolve()
    except Exception:
        return None


def external_notes_sources_enabled(config_data: dict[str, Any] | None = None) -> bool:
    def truthy(value: Any) -> bool:
        return str(value or "").strip().lower() in {"1", "true", "yes", "on"}

    env_value = os.getenv("ARES_WEBUI_EXTERNAL_NOTES_SOURCES", "")
    if env_value:
        return truthy(env_value)
    if config_data is None:
        from api.config import get_config

        config_data = get_config()
    if not isinstance(config_data, dict):
        return False
    return truthy(
        config_data.get("webui_external_notes_sources")
        or config_data.get("external_notes_sources")
        or config_data.get("notes_sources_drawer")
    )


def read_memory(*, session_id: str = "", workspace: str = "") -> dict[str, Any]:
    home = _active_home()
    memory_file = home / "memories" / "MEMORY.md"
    user_file = home / "memories" / "USER.md"
    soul_file = home / "SOUL.md"

    def read(path: Path) -> str:
        return path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""

    context = read_active_project_context(
        resolve_project_context_workspace(session_id=session_id, workspace=workspace)
    )
    return {
        "memory": _redact_text(read(memory_file)),
        "user": _redact_text(read(user_file)),
        "soul": _redact_text(read(soul_file)),
        "project_context": _redact_text(context["content"]),
        "memory_path": str(memory_file),
        "user_path": str(user_file),
        "soul_path": str(soul_file),
        "project_context_path": context["path"],
        "project_context_name": context.get("name", ""),
        "project_context_workspace": context["workspace"],
        "memory_mtime": memory_file.stat().st_mtime if memory_file.exists() else None,
        "user_mtime": user_file.stat().st_mtime if user_file.exists() else None,
        "soul_mtime": soul_file.stat().st_mtime if soul_file.exists() else None,
        "project_context_mtime": context["mtime"],
        "project_context_shadowed": context["shadowed"],
        "external_notes_enabled": external_notes_sources_enabled(),
    }


def write_memory(section: str, content: str) -> dict[str, Any]:
    home = _active_home()
    memory_dir = home / "memories"
    memory_dir.mkdir(parents=True, exist_ok=True)
    targets = {
        "memory": memory_dir / "MEMORY.md",
        "user": memory_dir / "USER.md",
        "soul": home / "SOUL.md",
    }
    target = targets.get(section)
    if target is None:
        raise MemoryStoreError('section must be "memory", "user", or "soul"')
    if target.is_symlink():
        raise MemoryStoreError("Cannot write to a symlinked memory file")
    try:
        target.write_text(content, encoding="utf-8")
    except OSError as exc:
        if not isinstance(exc, PermissionError) and exc.errno != errno.EROFS:
            raise
        mode_hint = ""
        try:
            mode_hint = f" (mode {target.stat().st_mode & 0o777:o})"
        except OSError:
            pass
        raise MemoryStoreError(
            (
                f"{target.name} is not writable{mode_hint}: {target}. "
                "Run chmod 644 on the file or fix ownership on the shared volume."
            ),
            403,
        ) from exc

    try:
        from api.config import get_config
        from api.context_store import is_enabled, spawn_background_reindex

        config_data = get_config()
        if is_enabled(config_data):
            # Resolve home/config on THIS (calling) thread before spawning --
            # profile_scope is thread-local and does not propagate to a new
            # thread, so re-resolving inside the worker would silently target
            # the wrong profile (see api/streaming.py's _get_config_for_home
            # comment for the same bug class fixed once already).
            spawn_background_reindex(section, section, str(target), content, home=home, config_data=config_data)
    except Exception:
        logger.debug("Context Store background reindex could not be scheduled for %s", section, exc_info=True)

    return {"ok": True, "section": section, "path": str(target)}


# Compatibility aliases for regression tests migrating away from api.routes.
_read_active_project_context = read_active_project_context
_project_context_candidates = project_context_candidates


__all__ = [
    "MemoryStoreError",
    "external_notes_sources_enabled",
    "read_active_project_context",
    "read_memory",
    "resolve_project_context_workspace",
    "write_memory",
]
