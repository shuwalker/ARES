"""React production-build serving for the FastAPI application.

This module intentionally owns no API routes. It is included after every API
router so the SPA fallback can never shadow a backend endpoint.
"""

from __future__ import annotations

import json
import mimetypes
from collections.abc import Callable
from pathlib import Path

from fastapi import APIRouter, Request
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response


DEFAULT_FRONTEND_ROOT = Path(__file__).resolve().parents[1] / "frontend" / "dist"
RUNTIME_CONFIG_PLACEHOLDER = "__ARES_RUNTIME_CONFIG_JSON__"

_FRONTEND_ASSET_PREFIXES = ("assets/", "fonts/")
_FRONTEND_ROOT_ASSETS = {
    "apple-touch-icon.png",
    "favicon-192.png",
    "favicon-512.png",
    "favicon.svg",
    "robots.txt",
    "site.webmanifest",
}
_FRONTEND_FILE_SUFFIXES = {
    ".css",
    ".gif",
    ".html",
    ".ico",
    ".jpeg",
    ".jpg",
    ".js",
    ".json",
    ".map",
    ".png",
    ".svg",
    ".txt",
    ".webmanifest",
    ".webp",
    ".woff",
    ".woff2",
}
_MANIFEST_ALIASES = {
    "manifest.json",
    "manifest.webmanifest",
    "session/manifest.json",
    "session/manifest.webmanifest",
}

CsrfTokenResolver = Callable[[Request], str]


def csrf_token_for_request(request: Request) -> str:
    """Resolve the current cookie session's CSRF token.

    Trusted-proxy session establishment remains with the legacy authentication
    layer until authentication middleware is ported. Ordinary authenticated
    cookie sessions already receive the same token as the current server.
    """
    try:
        from api.auth import (
            _resolve_cookie_name,
            csrf_token_for_session,
            is_auth_enabled,
            verify_session,
        )

        if not is_auth_enabled():
            return ""
        cookie_value = request.cookies.get(_resolve_cookie_name())
        if cookie_value and verify_session(cookie_value):
            return csrf_token_for_session(cookie_value) or ""
    except Exception:
        pass
    return ""


def _json_not_found(message: str = "not found") -> JSONResponse:
    return JSONResponse({"error": message}, status_code=404)


def _is_api_path(path: str) -> bool:
    return path == "api" or path.startswith("api/")


def _is_asset_path(path: str) -> bool:
    if _is_api_path(path):
        return False
    return (
        path.startswith(_FRONTEND_ASSET_PREFIXES)
        or path in _FRONTEND_ROOT_ASSETS
        or Path(path).suffix.lower() in _FRONTEND_FILE_SUFFIXES
    )


def _resolve_file(root: Path, relative_path: str) -> Path | None:
    root = root.resolve()
    candidate = (root / relative_path).resolve()
    try:
        candidate.relative_to(root)
    except ValueError:
        return None
    return candidate if candidate.is_file() else None


def _media_type(path: Path) -> str:
    suffix = path.suffix.lower()
    if suffix == ".js":
        return "application/javascript"
    if suffix == ".webmanifest":
        return "application/manifest+json"
    guessed, _ = mimetypes.guess_type(path.name)
    return guessed or "application/octet-stream"


def _frontend_file(root: Path, path: str) -> Response:
    target = _resolve_file(root, path)
    if target is None:
        return _json_not_found()
    cache_control = (
        "public, max-age=31536000, immutable"
        if path.startswith("assets/")
        else "public, max-age=300"
    )
    return FileResponse(
        target,
        media_type=_media_type(target),
        headers={
            "Cache-Control": cache_control,
            "X-ARES-Frontend": "react",
            "X-Content-Type-Options": "nosniff",
        },
    )


def _manifest(root: Path) -> Response:
    manifest = _resolve_file(root, "site.webmanifest")
    if manifest is None:
        return _json_not_found()
    return FileResponse(
        manifest,
        media_type="application/manifest+json",
        headers={
            "Cache-Control": "no-store",
            "X-ARES-Frontend": "react",
            "X-Content-Type-Options": "nosniff",
        },
    )


def _spa_shell(root: Path, request: Request, resolve_csrf: CsrfTokenResolver) -> Response:
    index_path = _resolve_file(root, "index.html")
    if index_path is None:
        return _json_not_found("React frontend build not found")
    try:
        html = index_path.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        return HTMLResponse(
            "<!doctype html><title>ARES unavailable</title>"
            "<h1>Ares is restarting</h1><p>Please retry in a moment.</p>",
            status_code=503,
            headers={"Cache-Control": "no-store"},
        )
    runtime_config = (
        "{csrfToken:"
        + json.dumps(resolve_csrf(request), ensure_ascii=False)
        + "}"
    ).replace("<", "\\u003c")
    return HTMLResponse(
        html.replace(RUNTIME_CONFIG_PLACEHOLDER, runtime_config),
        headers={
            "Cache-Control": "no-store",
            "X-ARES-Frontend": "react",
        },
    )


def create_frontend_router(
    *,
    frontend_root: Path | None = None,
    csrf_resolver: CsrfTokenResolver | None = None,
) -> APIRouter:
    """Create the final catch-all router for the React application."""
    root = Path(frontend_root or DEFAULT_FRONTEND_ROOT)
    resolve_csrf = csrf_resolver or csrf_token_for_request
    router = APIRouter(include_in_schema=False)

    @router.api_route("/{path:path}", methods=["GET", "HEAD"])
    async def serve_frontend(request: Request, path: str) -> Response:
        clean_path = path.lstrip("/")

        # This guard is required even though API routers are registered first:
        # unknown API routes must remain JSON 404s and never become SPA HTML.
        if _is_api_path(clean_path):
            return _json_not_found()
        from .vite_proxy import proxy_vite_request

        vite_response = await proxy_vite_request(request)
        if vite_response is not None:
            return vite_response
        if clean_path in _MANIFEST_ALIASES:
            return _manifest(root)
        if _is_asset_path(clean_path):
            return _frontend_file(root, clean_path)
        return _spa_shell(root, request, resolve_csrf)

    return router
