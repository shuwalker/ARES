"""Brain transport — migrate existing Hermes data into ARES's runtime directory.

This is a ONE-TIME operation. It copies (never moves) data from the legacy
~/.hermes/ directory into ~/.ares/.hermes/. The originals are preserved so
nothing can break.

If ARES's HERMES_HOME already has data, this is a no-op.
"""

from __future__ import annotations

import shutil
from pathlib import Path

from .launcher import ARES_HOME, HERMES_HOME

LEGACY_HERMES_HOME = Path.home() / ".hermes"


def is_migrated() -> bool:
    """Check if brain transport has already been done."""
    return HERMES_HOME.exists() and (HERMES_HOME / "config.yaml").exists()


def transport_brain(
    source: Path | None = None,
    target: Path | None = None,
    force: bool = False,
) -> dict:
    """Copy Hermes brain data (config, skills, state, sessions) into ARES.

    Args:
        source: Legacy HERMES_HOME to copy from. Defaults to ~/.hermes/
        target: ARES HERMES_HOME to copy into. Defaults to ~/.ares/.hermes/
        force: If True, overwrite existing files. Default: skip existing.

    Returns:
        Dict with 'copied', 'skipped', 'errors' lists.
    """
    source = source or LEGACY_HERMES_HOME
    target = target or HERMES_HOME

    result = {"copied": [], "skipped": [], "errors": []}

    if not source.exists():
        result["errors"].append(f"Source directory does not exist: {source}")
        return result

    # These directories/files from ~/.hermes/ that we want to transport
    transport_items = {
        "config.yaml": source / "config.yaml",
        "skills": source / "skills",
        "state": source / "state",
        "sessions": source / "sessions",
        ".env": source / ".env",
    }

    target.mkdir(parents=True, exist_ok=True)

    for name, src_path in transport_items.items():
        if not src_path.exists():
            result["skipped"].append(f"{name} (not found at {src_path})")
            continue

        dst_path = target / name

        try:
            if src_path.is_dir():
                if dst_path.exists() and not force:
                    # Merge: copy contents, skip existing files
                    _merge_dirs(src_path, dst_path, result)
                else:
                    if dst_path.exists():
                        shutil.rmtree(dst_path)
                    shutil.copytree(src_path, dst_path)
                    result["copied"].append(f"{name}/ (full directory)")
            else:
                # File
                if dst_path.exists() and not force:
                    result["skipped"].append(f"{name} (already exists)")
                else:
                    shutil.copy2(src_path, dst_path)
                    result["copied"].append(name)
        except Exception as e:
            result["errors"].append(f"{name}: {e}")

    # Create ARES-specific directories that don't exist in legacy Hermes
    ares_dirs = [
        ARES_HOME / "memory",
        ARES_HOME / "profiles",
        ARES_HOME / "workspace",
        ARES_HOME / "trajectories",
        ARES_HOME / "logs",
    ]
    for d in ares_dirs:
        d.mkdir(parents=True, exist_ok=True)

    return result


def _merge_dirs(src: Path, dst: Path, result: dict) -> None:
    """Copy directory contents, skipping existing files (no overwrite by default)."""
    for item in src.rglob("*"):
        if item.is_dir():
            continue

        relative = item.relative_to(src)
        target_file = dst / relative
        target_file.parent.mkdir(parents=True, exist_ok=True)

        if target_file.exists():
            result["skipped"].append(str(relative))
        else:
            shutil.copy2(item, target_file)
            result["copied"].append(str(relative))


def get_transport_status() -> dict:
    """Check the current state of legacy vs ARES brain data."""
    legacy = LEGACY_HERMES_HOME
    ares = HERMES_HOME

    return {
        "legacy_exists": legacy.exists(),
        "legacy_dir": str(legacy),
        "ares_exists": ares.exists(),
        "ares_dir": str(ares),
        "ares_has_config": (ares / "config.yaml").exists() if ares.exists() else False,
        "ares_has_skills": (ares / "skills").exists() if ares.exists() else False,
        "ares_has_state": (ares / "state").exists() if ares.exists() else False,
        "is_migrated": is_migrated(),
        "legacy_items": _list_legacy_items(),
    }


def _list_legacy_items() -> list[str]:
    """List transportable items in the legacy ~/.hermes/ directory."""
    if not LEGACY_HERMES_HOME.exists():
        return []

    items = []
    for name in ["config.yaml", "skills", "state", "sessions", ".env"]:
        path = LEGACY_HERMES_HOME / name
        if path.exists():
            if path.is_dir():
                count = sum(1 for _ in path.rglob("*") if _.is_file())
                items.append(f"{name}/ ({count} files)")
            else:
                size = path.stat().st_size
                items.append(f"{name} ({size} bytes)")
        else:
            items.append(f"{name} (not found)")
    return items