"""ARES-owned parsing and discovery primitives for shared skill resources."""

from __future__ import annotations

import os
from pathlib import Path
import sys
from typing import Any, Iterator

import yaml


MAX_DESCRIPTION_LENGTH = 500
EXCLUDED_SKILL_DIRS = frozenset(
    {
        ".git",
        ".hg",
        ".svn",
        ".tox",
        ".venv",
        "__pycache__",
        "node_modules",
        "site-packages",
    }
)
SKILL_SUPPORT_DIRS = frozenset({"assets", "references", "scripts", "templates"})


def iter_skill_index_files(root: Path, filename: str = "SKILL.md") -> Iterator[Path]:
    """Walk a skill tree without following directory cycles or dependency trees."""
    pending = [Path(root)]
    visited: set[tuple[int, int]] = set()
    while pending:
        directory = pending.pop()
        try:
            stat = directory.stat()
        except OSError:
            continue
        identity = (stat.st_dev, stat.st_ino)
        if identity in visited:
            continue
        visited.add(identity)
        try:
            entries = list(os.scandir(directory))
        except OSError:
            continue
        index = next((entry for entry in entries if entry.name == filename and entry.is_file()), None)
        if index is not None:
            yield Path(index.path)
        for entry in reversed(entries):
            if entry.name in EXCLUDED_SKILL_DIRS:
                continue
            if index is not None and entry.name in SKILL_SUPPORT_DIRS:
                continue
            try:
                if entry.is_dir(follow_symlinks=True):
                    pending.append(Path(entry.path))
            except OSError:
                continue


def parse_frontmatter(content: str) -> tuple[dict[str, Any], str]:
    """Parse YAML frontmatter while treating malformed metadata as invalid input."""
    text = str(content or "")
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        return {}, text
    closing = next((index for index, line in enumerate(lines[1:], 1) if line.strip() == "---"), None)
    if closing is None:
        raise ValueError("Unterminated skill frontmatter")
    metadata = yaml.safe_load("".join(lines[1:closing])) or {}
    if not isinstance(metadata, dict):
        raise ValueError("Skill frontmatter must be a mapping")
    return metadata, "".join(lines[closing + 1 :])


def parse_tags(value: Any) -> list[str]:
    if value is None:
        return []
    values = value if isinstance(value, (list, tuple, set)) else str(value).split(",")
    return list(dict.fromkeys(str(item).strip() for item in values if str(item).strip()))


def skill_matches_platform(frontmatter: dict[str, Any]) -> bool:
    """Return whether a skill declares compatibility with this host or WebUI."""
    metadata = frontmatter.get("metadata") if isinstance(frontmatter, dict) else None
    ares_metadata = metadata.get("ares") if isinstance(metadata, dict) else None
    declared = frontmatter.get("platforms") if isinstance(frontmatter, dict) else None
    if declared is None and isinstance(ares_metadata, dict):
        declared = ares_metadata.get("platforms")
    platforms = {item.lower() for item in parse_tags(declared)}
    if not platforms or platforms & {"all", "any", "webui"}:
        return True
    current = "windows" if sys.platform.startswith("win") else "macos" if sys.platform == "darwin" else "linux"
    aliases = {
        "macos": {"darwin", "mac", "macos", "osx"},
        "windows": {"win", "win32", "windows"},
        "linux": {"linux"},
    }
    return bool(platforms & aliases[current])


def sort_skills(skills: list[dict[str, Any]]) -> list[dict[str, Any]]:
    return sorted(
        skills,
        key=lambda row: (
            str(row.get("category") or "").casefold(),
            str(row.get("name") or "").casefold(),
        ),
    )
