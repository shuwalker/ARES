"""Bounded multipart upload and speech-processing endpoints."""

from __future__ import annotations

import asyncio
from io import BytesIO
from typing import Annotated

from fastapi import APIRouter, Depends, Request

from api.config import MAX_UPLOAD_BYTES
from api.upload import UploadServiceError, parse_multipart

from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_identity, require_mutation_identity


router = APIRouter(prefix="/api", tags=["uploads"])


async def _multipart(request: Request) -> tuple[dict, dict]:
    content_type = request.headers.get("content-type", "")
    raw_length = request.headers.get("content-length")
    if raw_length:
        try:
            declared_length = int(raw_length)
        except ValueError as exc:
            raise CoreApiError(400, "Invalid Content-Length") from exc
        if declared_length < 0:
            raise CoreApiError(400, "Invalid Content-Length (negative)")
        if declared_length > MAX_UPLOAD_BYTES:
            raise CoreApiError(413, f"File too large (max {MAX_UPLOAD_BYTES//1024//1024}MB)")
    chunks = bytearray()
    async for chunk in request.stream():
        chunks.extend(chunk)
        if len(chunks) > MAX_UPLOAD_BYTES:
            raise CoreApiError(413, f"File too large (max {MAX_UPLOAD_BYTES//1024//1024}MB)")
    try:
        return parse_multipart(BytesIO(chunks), content_type, len(chunks))
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc


def _file(files: dict) -> tuple[str, bytes]:
    value = files.get("file")
    if not value:
        raise CoreApiError(400, "No file field in request")
    filename, content = value
    if not filename:
        raise CoreApiError(400, "No filename in upload")
    return filename, content


def _service_error(exc: UploadServiceError) -> CoreApiError:
    status = 400 if str(exc) == "Upload target escapes workspace" else exc.status_code
    return CoreApiError(status, str(exc))


def _profile_call(profile: str | None, operation, *args):
    with profile_scope(profile):
        return operation(*args)


@router.post("/upload")
async def upload(
    request: Request,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.upload import save_session_upload

    fields, files = await _multipart(request)
    filename, content = _file(files)
    try:
        return await asyncio.to_thread(
            _profile_call,
            identity.profile,
            save_session_upload,
            fields.get("session_id", ""),
            filename,
            content,
        )
    except UploadServiceError as exc:
        raise _service_error(exc) from exc


@router.post("/upload/extract")
async def upload_extract(
    request: Request,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.upload import extract_session_upload

    fields, files = await _multipart(request)
    filename, content = _file(files)
    try:
        return await asyncio.to_thread(
            _profile_call,
            identity.profile,
            extract_session_upload,
            fields.get("session_id", ""),
            filename,
            content,
        )
    except UploadServiceError as exc:
        raise _service_error(exc) from exc


@router.post("/transcribe")
async def transcribe(
    request: Request,
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.upload import transcribe_upload

    _fields, files = await _multipart(request)
    filename, content = _file(files)
    try:
        return await asyncio.to_thread(transcribe_upload, filename, content)
    except UploadServiceError as exc:
        raise _service_error(exc) from exc


@router.post("/workspace/upload")
async def workspace_upload(
    request: Request,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.upload import save_workspace_upload

    fields, files = await _multipart(request)
    if not fields.get("session_id"):
        raise CoreApiError(400, "Missing session_id")
    if not files:
        raise CoreApiError(400, "No file field in request")
    try:
        return await asyncio.to_thread(
            _profile_call,
            identity.profile,
            save_workspace_upload,
            fields["session_id"],
            fields.get("path", ""),
            files,
        )
    except UploadServiceError as exc:
        raise _service_error(exc) from exc


@router.get("/transcribe/capability")
def transcribe_capability(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    from api.upload import _stt_provider_capability

    available, provider = _stt_provider_capability()
    return {"ok": True, "available": bool(available), "provider": provider}
