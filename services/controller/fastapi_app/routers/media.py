"""Authenticated media delivery and text-to-speech endpoints."""

from __future__ import annotations

import asyncio
import os
from typing import Annotated, Any

from fastapi import APIRouter, Body, Depends, Query, Request
from fastapi.responses import FileResponse, Response

from api.media_store import MediaStoreError, html_preview_with_blank_base, resolve_media
from api.tts_service import TtsServiceError, generate_tts, tts_rate_limiter

from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_identity


router = APIRouter(prefix="/api", tags=["media"])


def _profile_tts(profile: str | None, payload: dict[str, Any]):
    with profile_scope(profile):
        return generate_tts(payload)


def _profile_media(profile: str | None, path: str, session_id: str, inline: bool):
    with profile_scope(profile):
        return resolve_media(path, session_id=session_id, inline=inline)


def _read_html_preview(path):
    return html_preview_with_blank_base(path.read_bytes())


def _client_key(request: Request, identity: RequestIdentity) -> str:
    if identity.session_cookie and "." in identity.session_cookie:
        return identity.session_cookie.split(".", 1)[0]
    trust_proxy = os.getenv("ARES_WEBUI_TRUST_FORWARDED_FOR", "").strip().lower()
    if trust_proxy in {"1", "true", "yes", "on"}:
        for header in ("x-forwarded-for", "x-real-ip", "forwarded"):
            value = request.headers.get(header)
            if value:
                candidate = value.split(",", 1)[0].strip().split(";", 1)[0].strip()
                if candidate:
                    return candidate
    return str(getattr(request.client, "host", "") or "unknown")


@router.post("/tts")
async def tts(
    request: Request,
    payload: Annotated[dict[str, Any], Body()],
    identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    if not tts_rate_limiter.check(_client_key(request, identity)):
        raise CoreApiError(429, "rate limit exceeded — please wait")
    try:
        audio = await asyncio.to_thread(_profile_tts, identity.profile, payload)
    except TtsServiceError as exc:
        raise CoreApiError(exc.status_code, str(exc)) from exc
    return Response(
        content=audio.content,
        media_type=audio.media_type,
        headers={"Cache-Control": "no-store"},
    )


@router.get("/tts")
def tts_requires_post():
    raise CoreApiError(405, "POST required for /api/tts")


@router.get("/media")
async def media(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    path: Annotated[str, Query()] = "",
    session_id: Annotated[str, Query()] = "",
    inline: Annotated[str, Query()] = "",
):
    try:
        resolved = await asyncio.to_thread(
            _profile_media,
            identity.profile,
            path,
            session_id,
            inline == "1",
        )
    except MediaStoreError as exc:
        raise CoreApiError(exc.status_code, str(exc)) from exc
    headers = {
        "Cache-Control": "private, max-age=3600",
        "X-Content-Type-Options": "nosniff",
    }
    if resolved.content_security_policy:
        headers.update(
            {
                "Content-Security-Policy": resolved.content_security_policy,
                "Referrer-Policy": "same-origin",
                "Permissions-Policy": "camera=(), microphone=(self), geolocation=(), clipboard-write=(self)",
            }
        )
        return Response(
            await asyncio.to_thread(_read_html_preview, resolved.path),
            media_type="text/html",
            headers={
                **headers,
                "Content-Disposition": f'inline; filename="{resolved.path.name}"',
                "Accept-Ranges": "none",
            },
        )
    return FileResponse(
        resolved.path,
        media_type=resolved.media_type,
        filename=resolved.path.name,
        content_disposition_type=resolved.disposition,
        headers=headers,
    )
