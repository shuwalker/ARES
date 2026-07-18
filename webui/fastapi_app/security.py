"""HTTP security policy shared by API and React responses."""

from __future__ import annotations

from collections.abc import Awaitable, Callable
import json
import logging
import time

from fastapi import Request, Response
from fastapi.responses import JSONResponse


REPORT_TO = (
    '{"group":"csp-endpoint","max_age":10886400,'
    '"endpoints":[{"url":"/api/csp-report"}]}'
)
access_logger = logging.getLogger("webui.access")
_ORIGIN_CHECK_EXEMPT_PATHS = frozenset({"/api/auth/login", "/api/csp-report"})


async def security_headers_middleware(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    """Apply the legacy hardening contract at the ASGI boundary."""

    from api.helpers import (
        _build_csp_enforced_policy,
        _build_csp_report_only_policy,
        _csp_extra_connect_src,
        _csp_extra_frame_src,
    )

    started = time.perf_counter()
    if (
        request.url.path.startswith("/api/")
        and request.url.path not in _ORIGIN_CHECK_EXEMPT_PATHS
        and request.method not in {"GET", "HEAD", "OPTIONS"}
    ):
        from api.http_security import browser_origin_allowed

        if not browser_origin_allowed(request.headers):
            response = JSONResponse(
                {"error": "Cross-origin mismatch - check reverse proxy headers"},
                status_code=403,
            )
        else:
            response = await call_next(request)
    elif request.method == "OPTIONS":
        from api.http_security import browser_origin_allowed

        response = Response(status_code=200, content=b"")
        origin = str(request.headers.get("origin") or "").strip()
        if origin and browser_origin_allowed(request.headers):
            response.headers["Access-Control-Allow-Origin"] = origin
            response.headers["Vary"] = "Origin"
            response.headers["Access-Control-Allow-Methods"] = "GET, POST, PUT, PATCH, DELETE, OPTIONS"
            response.headers["Access-Control-Allow-Headers"] = "Content-Type, Authorization"
    else:
        response = await call_next(request)
    extra_connect = _csp_extra_connect_src()
    extra_frame = _csp_extra_frame_src()
    response.headers.setdefault("X-Content-Type-Options", "nosniff")
    response.headers.setdefault("X-Frame-Options", "DENY")
    response.headers.setdefault("Referrer-Policy", "same-origin")
    response.headers.setdefault(
        "Permissions-Policy",
        "camera=(), microphone=(self), geolocation=(), clipboard-write=(self)",
    )
    response.headers.setdefault(
        "Content-Security-Policy",
        _build_csp_enforced_policy(extra_connect, extra_frame),
    )
    response.headers.setdefault(
        "Content-Security-Policy-Report-Only",
        _build_csp_report_only_policy(extra_connect, extra_frame),
    )
    response.headers.setdefault("Report-To", REPORT_TO)
    record = {
        "remote": request.client.host if request.client else "-",
        "method": request.method or "-",
        "path": request.url.path or "-",
        "status": response.status_code,
        "ms": round((time.perf_counter() - started) * 1000, 1),
    }
    forwarded = str(request.headers.get("x-forwarded-for") or "").split(",", 1)[0].strip()
    if forwarded:
        record["forwarded_for"] = forwarded[:128]
    access_logger.info("[webui] %s", json.dumps(record, separators=(",", ":")))
    return response


__all__ = ["REPORT_TO", "security_headers_middleware"]
