"""Race-resistant workspace file mutations independent of HTTP transport."""

from __future__ import annotations

import os
import platform
import shutil
import subprocess
from pathlib import Path
from typing import Any


class FileOperationError(RuntimeError):
    def __init__(self, message: str, status_code: int = 400):
        super().__init__(message)
        self.status_code = status_code


def _workspace(session_id: str) -> tuple[Path, Any]:
    from api.models import get_session_for_file_ops
    from api.profiles import _profiles_match, get_active_profile_name

    try:
        session = get_session_for_file_ops(session_id)
    except KeyError as exc:
        raise FileOperationError("Session not found", 404) from exc
    if not _profiles_match(getattr(session, "profile", None), get_active_profile_name()):
        raise FileOperationError("Session not found", 404)
    return Path(session.workspace), session


def delete_file(session_id: str, path: str, *, recursive: bool = False) -> dict:
    from api.workspace import rmtree_anchored, safe_resolve_ws, unlink_anchored

    root, _session = _workspace(session_id)
    if (root / path).is_symlink():
        raise FileOperationError("Cannot delete a symlinked entry")
    target = safe_resolve_ws(root, path)
    if not target.exists():
        raise FileOperationError("File not found", 404)
    if target.is_dir():
        if not recursive:
            raise FileOperationError("Set recursive=true to delete directories")
        rmtree_anchored(root, target)
    else:
        unlink_anchored(root, target)
    return {"ok": True, "path": path}


def save_file(session_id: str, path: str, content: Any = "") -> dict:
    from api.workspace import open_anchored_write_fd, safe_resolve_ws

    root, _session = _workspace(session_id)
    if (root / path).is_symlink():
        raise FileOperationError("Cannot save to a symlinked entry")
    target = safe_resolve_ws(root, path)
    if not target.exists():
        raise FileOperationError("File not found", 404)
    if target.is_dir():
        raise FileOperationError("Cannot save: path is a directory")
    if Path(path).suffix.lower() in {".docx", ".xlsx", ".pptx"}:
        raise FileOperationError("Use /api/file/office-save for Office documents")
    data = str(content or "").encode("utf-8")
    descriptor = open_anchored_write_fd(root, target)
    with os.fdopen(descriptor, "wb", closefd=True) as output:
        output.write(data)
    return {"ok": True, "path": path, "size": len(data)}


def create_file(session_id: str, path: str, content: Any = "") -> dict:
    from api.workspace import open_anchored_create_fd, safe_resolve_ws

    root, _session = _workspace(session_id)
    target = safe_resolve_ws(root, path)
    if target.exists():
        raise FileOperationError("File already exists")
    data = str(content or "").encode("utf-8")
    try:
        descriptor = open_anchored_create_fd(root, target)
    except FileExistsError as exc:
        raise FileOperationError("File already exists") from exc
    with os.fdopen(descriptor, "wb", closefd=True) as output:
        output.write(data)
    return {"ok": True, "path": target.relative_to(root.resolve()).as_posix()}


def create_directory(session_id: str, path: str) -> dict:
    from api.workspace import make_anchored_dir, safe_resolve_ws

    root, _session = _workspace(session_id)
    target = safe_resolve_ws(root, path)
    if target.exists():
        raise FileOperationError("Path already exists")
    make_anchored_dir(root, target)
    return {"ok": True, "path": target.relative_to(root.resolve()).as_posix()}


def rename_file(session_id: str, path: str, new_name: str) -> dict:
    from api.workspace import rename_anchored, safe_resolve_ws

    root, _session = _workspace(session_id)
    if (root / path).is_symlink():
        raise FileOperationError("Cannot rename a symlinked entry")
    source = safe_resolve_ws(root, path)
    if not source.exists():
        raise FileOperationError("File not found", 404)
    new_name = str(new_name or "").strip()
    if not new_name or "/" in new_name or "\\" in new_name or ".." in new_name:
        raise FileOperationError("Invalid file name")
    destination = source.parent / new_name
    if destination.exists():
        raise FileOperationError(f'A file named "{new_name}" already exists')
    try:
        rename_anchored(root, source, destination)
    except FileExistsError as exc:
        raise FileOperationError(f'A file named "{new_name}" already exists') from exc
    return {
        "ok": True,
        "old_path": path,
        "new_path": destination.relative_to(root.resolve()).as_posix(),
    }


def move_file(session_id: str, path: str, destination_directory: str) -> dict:
    from api.workspace import open_anchored_fd, safe_resolve_ws

    root, _session = _workspace(session_id)
    resolved_root = root.resolve()
    if (root / path).is_symlink():
        raise FileOperationError("Cannot move a symlinked entry")
    source = safe_resolve_ws(root, path)
    if not source.exists():
        raise FileOperationError("File not found", 404)
    raw_destination = str(destination_directory or ".").strip() or "."
    if ".." in raw_destination.replace("\\", "/").split("/"):
        raise FileOperationError("Invalid destination")
    destination_parent = safe_resolve_ws(root, raw_destination)
    if not destination_parent.is_dir():
        raise FileOperationError("Destination folder not found", 404)
    if source.is_dir():
        try:
            destination_parent.resolve().relative_to(source.resolve())
        except ValueError:
            pass
        else:
            raise FileOperationError("Cannot move a folder into itself or its subfolder")
    destination = destination_parent / source.name
    if destination.resolve() == source.resolve():
        return {
            "ok": True,
            "old_path": path,
            "new_path": source.relative_to(resolved_root).as_posix(),
        }

    leaf = source.name
    if os.open in getattr(os, "supports_dir_fd", set()):
        source_parent_fd = open_anchored_fd(root, source.parent, want_dir=True)
        try:
            destination_parent_fd = open_anchored_fd(root, destination_parent, want_dir=True)
            try:
                try:
                    os.stat(leaf, dir_fd=destination_parent_fd, follow_symlinks=False)
                except FileNotFoundError:
                    pass
                else:
                    raise FileOperationError(
                        f'A file named "{leaf}" already exists in that folder'
                    )
                os.rename(
                    leaf,
                    leaf,
                    src_dir_fd=source_parent_fd,
                    dst_dir_fd=destination_parent_fd,
                )
            finally:
                os.close(destination_parent_fd)
        finally:
            os.close(source_parent_fd)
    else:
        if destination.exists():
            raise FileOperationError(
                f'A file named "{source.name}" already exists in that folder'
            )
        source.rename(destination)
    return {
        "ok": True,
        "old_path": path,
        "new_path": destination.relative_to(resolved_root).as_posix(),
    }


def resolve_file_path(session_id: str, path: str) -> dict:
    from api.workspace import safe_resolve_ws

    root, _session = _workspace(session_id)
    return {"ok": True, "path": str(safe_resolve_ws(root, path))}


def save_office_file(session_id: str, path: str, content: Any = "") -> dict:
    from api.config import MAX_FILE_BYTES
    from api.office_documents import save_office_document
    from api.workspace import open_anchored_fd, open_anchored_write_fd, safe_resolve_ws

    root, _session = _workspace(session_id)
    if (root / path).is_symlink():
        raise FileOperationError("Cannot save to a symlinked entry")
    target = safe_resolve_ws(root, path)
    if not target.exists():
        raise FileOperationError("File not found", 404)
    if target.is_dir():
        raise FileOperationError("Cannot save: path is a directory")
    if target.suffix.lower() not in {".docx", ".xlsx", ".pptx"}:
        raise FileOperationError("Office save is only available for .docx, .xlsx, and .pptx files")
    descriptor = open_anchored_fd(root, target, want_dir=False)
    with os.fdopen(descriptor, "rb", closefd=True) as source:
        current = source.read(MAX_FILE_BYTES + 1)
    if len(current) > MAX_FILE_BYTES:
        raise FileOperationError(f"File too large ({len(current)} bytes, max {MAX_FILE_BYTES})")
    preview, updated = save_office_document(path, current, content)
    descriptor = open_anchored_write_fd(root, target)
    with os.fdopen(descriptor, "wb", closefd=True) as output:
        output.write(updated)
    preview.update({"ok": True, "path": path, "size": len(updated)})
    return preview


def _translated_desktop_path(target: Path) -> tuple[str, dict]:
    from api.config import get_config

    vscode = get_config().get("vscode") or {}
    if not isinstance(vscode, dict):
        vscode = {}
    target_path = str(target)
    container = str(vscode.get("container_path_prefix") or "").rstrip("/")
    host = str(vscode.get("host_path_prefix") or "").rstrip("/")
    if container and host and (target_path == container or target_path.startswith(container + "/")):
        target_path = host + target_path[len(container) :]
    return target_path, vscode


def reveal_file(session_id: str, path: str) -> dict:
    from api.workspace import safe_resolve_ws

    root, _session = _workspace(session_id)
    target = safe_resolve_ws(root, path)
    if not target.exists():
        raise FileOperationError(f"File not found: {target}", 404)
    target_path, _vscode = _translated_desktop_path(target)
    system = platform.system()
    if system == "Darwin":
        command = ["open", "-R", target_path]
    elif system == "Windows":
        command = ["explorer.exe", "/select," + target_path]
    else:
        command = ["xdg-open", str(Path(target_path).parent)]
    subprocess.Popen(command)
    return {"ok": True, "path": path}


def open_in_vscode(session_id: str, path: str) -> dict:
    from api.workspace import safe_resolve_ws

    root, _session = _workspace(session_id)
    target = safe_resolve_ws(root, path)
    if not target.exists():
        raise FileOperationError(f"File not found: {target}", 404)
    target_path, vscode = _translated_desktop_path(target)
    configured = str(vscode.get("command") or "code")
    command = shutil.which(configured)
    if command is None:
        candidates = [
            "/usr/local/bin/code",
            "/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code",
            "/usr/bin/code",
            "/snap/bin/code",
        ]
        command = next((candidate for candidate in candidates if Path(candidate).exists()), None)
    if command is None:
        raise FileOperationError(
            f"VS Code command not found: {configured!r}. Install VS Code or configure vscode.command."
        )
    subprocess.Popen([command, target_path])
    return {"ok": True, "path": path}
