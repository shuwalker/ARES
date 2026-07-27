"""
ARES Journal — Volume scanner and NAS connector.

Scans mounted volumes for conversation data and other context sources.
Can also mount SMB/AFP shares on macOS using the diskutil/opensmb commands.
"""

import json
import os
import subprocess
import time
from pathlib import Path
from typing import Optional

from .schema import init_db


def list_volumes() -> list[dict]:
    """List all currently mounted volumes on macOS."""
    volumes = []
    volumes_dir = Path("/Volumes")

    if not volumes_dir.exists():
        return []

    for entry in sorted(volumes_dir.iterdir()):
        if entry.is_dir() or entry.is_mount():
            try:
                stat = entry.stat()
                usage = None
                # Try to get disk usage
                try:
                    result = subprocess.run(
                        ["df", "-h", str(entry)],
                        capture_output=True, text=True, timeout=5
                    )
                    if result.returncode == 0:
                        lines = result.stdout.strip().split("\n")
                        if len(lines) >= 2:
                            parts = lines[1].split()
                            if len(parts) >= 6:
                                usage = {
                                    "total": parts[1],
                                    "used": parts[2],
                                    "available": parts[3],
                                    "percent": parts[4],
                                }
                except Exception:
                    pass

                volumes.append({
                    "name": entry.name,
                    "path": str(entry),
                    "size_bytes": getattr(stat, "st_size", 0),
                    "usage": usage,
                    "mounted": True,
                })
            except (PermissionError, OSError):
                volumes.append({
                    "name": entry.name,
                    "path": str(entry),
                    "mounted": True,
                    "error": "Permission denied",
                })

    return volumes


def mount_smb(server: str, share: str, username: Optional[str] = None, password: Optional[str] = None) -> dict:
    """
    Mount an SMB share on macOS.

    Args:
        server: SMB server hostname or IP (e.g. "192.168.1.100" or "nas.local")
        share: Share name (e.g. "Jenkins_Robotics")
        username: Optional username for authentication
        password: Optional password (will prompt if needed and not provided)

    Returns:
        Dict with mount status and path.
    """
    mount_point = f"/Volumes/{share}"

    # Check if already mounted
    if Path(mount_point).is_mount() or Path(mount_point).exists():
        # Verify it's actually the right share
        try:
            result = subprocess.run(
                ["mount"], capture_output=True, text=True, timeout=5
            )
            for line in result.stdout.split("\n"):
                if share in line and server in line:
                    return {
                        "mounted": True,
                        "path": mount_point,
                        "status": "already_mounted",
                        "message": f"{share} is already mounted from {server}",
                    }
        except Exception:
            pass

    # Build the SMB URL
    if username:
        smb_url = f"smb://{username}@{server}/{share}"
    else:
        smb_url = f"smb://{server}/{share}"

    # Create mount point
    try:
        os.makedirs(mount_point, exist_ok=True)
    except OSError:
        pass

    # Use open to mount via Finder (handles keychain auth gracefully)
    # For non-interactive mounting, use mount_smbfs
    cmd = ["open", smb_url]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=10)
        if result.returncode == 0:
            return {
                "mounted": True,
                "path": mount_point,
                "status": "mount_requested",
                "message": f"Mount requested for {smb_url}. Check Finder for authentication prompt.",
            }
        else:
            return {
                "mounted": False,
                "path": mount_point,
                "status": "mount_failed",
                "message": f"Mount failed: {result.stderr.strip()}",
            }
    except Exception as e:
        return {
            "mounted": False,
            "path": mount_point,
            "status": "error",
            "message": str(e),
        }


def unmount(volume_path: str) -> dict:
    """Unmount a volume."""
    try:
        result = subprocess.run(
            ["umount", volume_path], capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            return {"unmounted": True, "path": volume_path}
        else:
            return {"unmounted": False, "path": volume_path, "error": result.stderr.strip()}
    except Exception as e:
        return {"unmounted": False, "path": volume_path, "error": str(e)}


def scan_volume(volume_path: str) -> dict:
    """
    Scan a mounted volume for conversation data sources.

    Looks for:
    - Hermes state.db
    - Claude Code sessions
    - Grok export directories
    - Codex session directories
    - Any SQLite databases that might contain conversations
    - Any JSONL files that might be chat logs
    """
    path = Path(volume_path)
    if not path.exists() or not path.is_dir():
        return {"error": f"Volume not found: {volume_path}"}

    findings = {
        "volume_path": str(path),
        "scanned_at": time.time(),
        "sources": [],
    }

    # Known conversation patterns to search for
    patterns = [
        ("hermes_state_db", "**/state.db"),
        ("claude_code_sessions", "**/.claude/projects/**/*.jsonl"),
        ("grok_export", "**/Grok-Conversation-Export*/INDEX.md"),
        ("codex_sessions", "**/.codex/sessions/**/*.jsonl"),
        ("codex_index", "**/.codex/session_index.jsonl"),
        ("sqlite_dbs", "**/*.db"),
        ("jsonl_chat", "**/*chat*.jsonl"),
        ("jsonl_conversation", "**/*conversation*.jsonl"),
    ]

    for source_type, pattern in patterns:
        try:
            matches = list(path.glob(pattern))[:50]  # Cap at 50 per pattern
            if matches:
                findings["sources"].append({
                    "type": source_type,
                    "pattern": pattern,
                    "count": len(matches),
                    "samples": [str(m) for m in matches[:5]],
                })
        except (PermissionError, OSError):
            continue

    return findings