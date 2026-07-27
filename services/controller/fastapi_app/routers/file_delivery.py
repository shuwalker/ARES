"""Workspace file reads, downloads, and authorized escape traversal."""

from __future__ import annotations

import os
import tempfile
import zipfile
from pathlib import Path
from typing import Annotated
from urllib.parse import quote

from fastapi import APIRouter, BackgroundTasks, Depends, Query, Request
from fastapi.responses import Response, StreamingResponse

from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_identity, require_mutation_identity


router = APIRouter(tags=["file-delivery"])


def _session_workspace(session_id: str) -> tuple[Path, object]:
    from api.models import get_session_for_file_ops

    try:
        session = get_session_for_file_ops(session_id)
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc
    return Path(session.workspace), session


def _translate_file_error(exc: Exception):
    from api.workspace import EscapeAuthorizationExpiredError

    if isinstance(exc, EscapeAuthorizationExpiredError):
        raise CoreApiError(403, str(exc)) from exc
    if isinstance(exc, ImportError):
        raise CoreApiError(503, str(exc)) from exc
    if isinstance(exc, (FileNotFoundError, ValueError)):
        raise CoreApiError(404, str(exc)) from exc
    raise exc


@router.get("/api/file")
def read_file(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
    path: str = Query(min_length=1, max_length=4096),
):
    from api.workspace import read_file_content

    with profile_scope(identity.profile):
        root, _session = _session_workspace(session_id)
        try:
            return read_file_content(root, path)
        except Exception as exc:
            _translate_file_error(exc)


def _content_disposition(disposition: str, filename: str) -> str:
    safe = Path(filename).name.replace("\r", "").replace("\n", "")
    fallback = "".join(char if 32 <= ord(char) < 127 and char not in {'"', '\\'} else "_" for char in safe)
    return f'{disposition}; filename="{fallback or "download"}"; filename*=UTF-8\'\'{quote(safe, safe="")}'


def _stream_file(root: Path, target: Path, *, download: bool, inline: bool, range_header: str = ""):
    from api.http_range import parse_range_header
    from api.config import MIME_MAP
    from api.workspace import open_anchored_fd

    try:
        descriptor = open_anchored_fd(root, target, want_dir=False)
    except (FileNotFoundError, ValueError, OSError) as exc:
        raise CoreApiError(404, "not found") from exc
    size = os.fstat(descriptor).st_size
    byte_range = parse_range_header(range_header, size)
    if range_header and byte_range is None:
        os.close(descriptor)
        return Response(
            status_code=416,
            headers={"Content-Range": f"bytes */{size}", "Accept-Ranges": "bytes"},
        )
    start, end = byte_range if byte_range else (0, max(size - 1, 0))
    content_length = end - start + 1 if size else 0
    mime = MIME_MAP.get(target.suffix.lower(), "application/octet-stream")
    dangerous_types = {"text/html", "application/xhtml+xml", "image/svg+xml"}
    html_inline = inline and mime == "text/html"
    disposition = "attachment" if download or (mime in dangerous_types and not html_inline) else "inline"

    def chunks():
        with os.fdopen(descriptor, "rb", closefd=True) as source:
            source.seek(start)
            remaining = content_length
            while remaining:
                chunk = source.read(min(1024 * 1024, remaining))
                if not chunk:
                    return
                remaining -= len(chunk)
                yield chunk

    headers = {
        "Cache-Control": "no-store",
        "Content-Disposition": _content_disposition(disposition, target.name),
        "Content-Length": str(content_length),
        "Accept-Ranges": "bytes",
    }
    if byte_range:
        headers["Content-Range"] = f"bytes {start}-{end}/{size}"
    if html_inline:
        headers["Content-Security-Policy"] = "sandbox allow-scripts allow-popups allow-popups-to-escape-sandbox"
    return StreamingResponse(chunks(), media_type=mime, headers=headers, status_code=206 if byte_range else 200)


def _workspace_raw_target(session_id: str, path: str) -> tuple[Path, Path]:
    from api.upload import _session_attachment_dir
    from api.workspace import safe_resolve_ws

    root, _session = _session_workspace(session_id)
    try:
        target = safe_resolve_ws(root, path)
    except ValueError:
        target = None
    if target is not None and target.is_file():
        return root, target
    attachment_root = _session_attachment_dir(session_id)
    target = safe_resolve_ws(attachment_root, path)
    if target.is_file():
        return attachment_root, target
    raise CoreApiError(404, "not found")


@router.get("/api/file/raw")
def raw_file(
    request: Request,
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
    path: str = Query(min_length=1, max_length=4096),
    download: bool = False,
    inline: bool = False,
):
    with profile_scope(identity.profile):
        root, target = _workspace_raw_target(session_id, path)
        return _stream_file(
            root,
            target,
            download=download,
            inline=inline,
            range_header=request.headers.get("range", ""),
        )


@router.post("/api/escape/authorize")
def authorize_escape(
    payload: dict,
    request: Request,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.workspace import authorize_escape_target

    if not request.headers.get("Origin"):
        raise CoreApiError(403, "browser origin required")
    if payload.get("token"):
        raise CoreApiError(400, "token must not be provided")
    session_id = str(payload.get("session_id") or "").strip()
    path = str(payload.get("path") or "").strip()
    if not session_id or not path:
        raise CoreApiError(400, "session_id and path are required")
    with profile_scope(identity.profile):
        root, _session = _session_workspace(session_id)
        try:
            return authorize_escape_target(root, session_id, path)
        except ValueError as exc:
            raise CoreApiError(404, str(exc)) from exc


@router.get("/api/escape/list")
def list_escape(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
    token: str = Query(min_length=1, max_length=512),
    path: str = Query(default=".", max_length=4096),
):
    from api.workspace import list_authorized_escape_dir

    with profile_scope(identity.profile):
        root, _session = _session_workspace(session_id)
        try:
            return list_authorized_escape_dir(root, session_id, token, path)
        except Exception as exc:
            _translate_file_error(exc)


@router.get("/api/escape/file/read")
def read_escape_file(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
    token: str = Query(min_length=1, max_length=512),
    path: str = Query(min_length=1, max_length=4096),
):
    from api.workspace import read_authorized_escape_file_content

    with profile_scope(identity.profile):
        root, _session = _session_workspace(session_id)
        try:
            return read_authorized_escape_file_content(root, session_id, token, path)
        except Exception as exc:
            _translate_file_error(exc)


@router.get("/api/escape/file/raw")
def raw_escape_file(
    request: Request,
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
    token: str = Query(min_length=1, max_length=512),
    path: str = Query(min_length=1, max_length=4096),
    download: bool = False,
    inline: bool = False,
):
    from api.workspace import raw_authorized_escape_target

    with profile_scope(identity.profile):
        root, _session = _session_workspace(session_id)
        try:
            anchor, target = raw_authorized_escape_target(root, session_id, token, path)
        except Exception as exc:
            _translate_file_error(exc)
        return _stream_file(
            anchor,
            target,
            download=download,
            inline=inline,
            range_header=request.headers.get("range", ""),
        )


@router.get("/api/folder/download")
def folder_download(
    background: BackgroundTasks,
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
    path: str = Query(default="", max_length=4096),
):
    from api.workspace import open_anchored_fd, safe_resolve_ws

    with profile_scope(identity.profile):
        root, _session = _session_workspace(session_id)
        target = safe_resolve_ws(root, path)
        if not target.exists():
            raise CoreApiError(404, "not found")
        if not target.is_dir():
            raise CoreApiError(400, "path must be a directory")
        max_bytes = max(1, int(os.getenv("ARES_WEBUI_FOLDER_ZIP_MAX_MB", "1024"))) * 1024 * 1024
        max_files = max(1, int(os.getenv("ARES_WEBUI_FOLDER_ZIP_MAX_FILES", "50000")))
        files = []
        total = 0
        for current, directories, names in os.walk(target, followlinks=False):
            current_path = Path(current)
            directories[:] = [name for name in directories if not (current_path / name).is_symlink()]
            for name in names:
                candidate = current_path / name
                if candidate.is_symlink():
                    continue
                size = candidate.stat().st_size
                if len(files) >= max_files:
                    raise CoreApiError(413, "too many files", context={"limit": max_files})
                if total + size > max_bytes:
                    raise CoreApiError(413, "folder too large", context={"limit_bytes": max_bytes})
                files.append((candidate, candidate.relative_to(target).as_posix()))
                total += size
        descriptor, archive_name = tempfile.mkstemp(prefix="ares-folder-", suffix=".zip")
        os.close(descriptor)
        try:
            with zipfile.ZipFile(archive_name, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as archive:
                for candidate, relative in files:
                    fd = open_anchored_fd(root, candidate, want_dir=False)
                    with os.fdopen(fd, "rb", closefd=True) as source, archive.open(relative, "w") as output:
                        while True:
                            chunk = source.read(1024 * 1024)
                            if not chunk:
                                break
                            output.write(chunk)
        except Exception:
            Path(archive_name).unlink(missing_ok=True)
            raise
    background.add_task(Path(archive_name).unlink, missing_ok=True)

    def chunks():
        with open(archive_name, "rb") as source:
            while True:
                chunk = source.read(1024 * 1024)
                if not chunk:
                    return
                yield chunk

    return StreamingResponse(
        chunks(),
        media_type="application/zip",
        headers={
            "Content-Disposition": _content_disposition("attachment", (target.name or "workspace") + ".zip"),
            "Cache-Control": "no-store",
        },
        background=background,
    )


__all__ = ["router"]
