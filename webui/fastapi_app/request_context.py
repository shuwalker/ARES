"""Authentication, CSRF, and profile context for the parallel application."""

from __future__ import annotations

from contextlib import contextmanager
from dataclasses import dataclass
import os
from typing import Annotated, Iterator
from urllib.parse import urlsplit

from fastapi import Depends, Request, Response
from starlette.requests import HTTPConnection

from .errors import CoreApiError


@dataclass(frozen=True)
class RequestIdentity:
    session_cookie: str | None
    profile: str | None
    auth_enabled: bool
    auth_type: str | None = None
    username: str | None = None
    bound_profile: str | None = None


def _set_auth_cookie(response: Response, request: HTTPConnection, cookie_value: str) -> None:
    from api.auth import _resolve_cookie_name, _resolve_session_ttl

    response.set_cookie(
        _resolve_cookie_name(),
        cookie_value,
        httponly=True,
        secure=str(getattr(getattr(request, "url", None), "scheme", "")) == "https",
        samesite="lax",
        path="/",
        max_age=_resolve_session_ttl(),
    )


def _trusted_session(
    request: HTTPConnection,
    response: Response | None,
    cookie_value: str | None,
):
    from api.auth import (
        _trusted_auth_bound_profile,
        _trusted_auth_username,
        create_session,
        get_session_info,
        invalidate_session,
        is_trusted_auth_enabled,
        verify_session,
    )
    from api.network_trust import raw_peer_is_trusted_proxy

    info = get_session_info(cookie_value or "") if cookie_value else None
    if cookie_value and info is None and verify_session(cookie_value):
        info = {"auth_type": None, "username": None, "bound_profile": None}
    if info and info.get("auth_type") != "trusted":
        return cookie_value, info
    if not is_trusted_auth_enabled() or not raw_peer_is_trusted_proxy(request):
        if info and cookie_value:
            invalidate_session(cookie_value)
        return None, None
    username = _trusted_auth_username(request)
    if not username:
        if info and cookie_value:
            invalidate_session(cookie_value)
        return None, None
    bound_profile = _trusted_auth_bound_profile(request)
    if info and info.get("username") == username and info.get("bound_profile") == bound_profile:
        return cookie_value, info
    if info and cookie_value:
        invalidate_session(cookie_value)
    cookie_value = create_session(
        auth_type="trusted",
        username=username,
        bound_profile=bound_profile,
    )
    if response is not None:
        _set_auth_cookie(response, request, cookie_value)
    return cookie_value, get_session_info(cookie_value)


def resolve_request_identity(
    request: HTTPConnection,
    response: Response | None = None,
    *,
    allow_anonymous: bool = False,
) -> RequestIdentity:
    from api.auth import (
        _resolve_cookie_name,
        get_session_info,
        is_auth_enabled,
        verify_profile_cookie_value,
        verify_session,
    )
    from api.helpers import get_profile_cookie_name
    from api.profiles import _PROFILE_ID_RE

    auth_enabled = is_auth_enabled()
    session_cookie = request.cookies.get(_resolve_cookie_name())
    verified_cookie = bool(session_cookie and verify_session(session_cookie))
    info = get_session_info(session_cookie) if verified_cookie else None
    # Some external/session-store adapters expose verification without extended
    # metadata. A verified ordinary cookie is still a valid authenticated
    # session; metadata is optional unless trusted-header binding is in use.
    if verified_cookie and info is None:
        info = {"auth_type": None, "username": None, "bound_profile": None}
    if auth_enabled:
        session_cookie, info = _trusted_session(request, response, session_cookie)
    if auth_enabled and not info and not allow_anonymous:
        raise CoreApiError(401, "Authentication required")

    raw_profile = request.cookies.get(get_profile_cookie_name())
    profile = None
    bound_profile = str((info or {}).get("bound_profile") or "").strip() or None
    if bound_profile:
        profile = bound_profile
        if response is not None and session_cookie:
            from api.helpers import build_profile_cookie

            response.headers.append(
                "set-cookie",
                build_profile_cookie(
                    bound_profile,
                    session_cookie_value=session_cookie,
                ),
            )
    elif raw_profile:
        if auth_enabled:
            profile = verify_profile_cookie_value(raw_profile, session_cookie)
        elif raw_profile == "default" or _PROFILE_ID_RE.fullmatch(raw_profile):
            profile = raw_profile
    return RequestIdentity(
        session_cookie,
        profile,
        auth_enabled,
        str((info or {}).get("auth_type") or "").strip() or None,
        str((info or {}).get("username") or "").strip() or None,
        bound_profile,
    )


def require_identity(request: Request, response: Response) -> RequestIdentity:
    return resolve_request_identity(request, response)


def require_mutation_identity(
    request: Request,
    identity: Annotated[RequestIdentity, Depends(require_identity)],
) -> RequestIdentity:
    from api.http_security import browser_origin_allowed

    if not browser_origin_allowed(request.headers):
        raise CoreApiError(403, "Cross-origin mismatch - check reverse proxy headers")
    if not identity.auth_enabled:
        return identity

    from api.auth import CSRF_HEADER_NAME, verify_csrf_token

    csrf_token = request.headers.get(CSRF_HEADER_NAME, "")
    if not identity.session_cookie or not verify_csrf_token(identity.session_cookie, csrf_token):
        raise CoreApiError(403, "Invalid CSRF token")
    return identity


def _same_origin_websocket(connection: HTTPConnection) -> bool:
    origin = str(connection.headers.get("origin") or "").strip()
    host = str(connection.headers.get("host") or "").strip().lower()
    if not origin or not host:
        return False
    try:
        return urlsplit(origin).netloc.lower() == host
    except ValueError:
        return False


def websocket_identity(connection: HTTPConnection) -> RequestIdentity:
    """Authenticate a browser WebSocket without putting CSRF data in its URL."""

    if not _same_origin_websocket(connection):
        raise CoreApiError(403, "WebSocket origin is not allowed")
    identity = resolve_request_identity(connection)
    if not identity.auth_enabled:
        return identity

    from api.auth import verify_csrf_token

    protocols = [
        item.strip()
        for item in str(connection.headers.get("sec-websocket-protocol") or "").split(",")
        if item.strip()
    ]
    csrf_token = next(
        (item.removeprefix("ares.csrf.") for item in protocols if item.startswith("ares.csrf.")),
        "",
    )
    if not identity.session_cookie or not verify_csrf_token(identity.session_cookie, csrf_token):
        raise CoreApiError(403, "Invalid WebSocket CSRF token")
    return identity


def connection_is_local_or_authenticated(
    connection: HTTPConnection,
    identity: RequestIdentity,
) -> bool:
    """Protect PTY access when the WebUI intentionally has no authentication."""

    from api.network_trust import embedded_terminal_gate_allows

    return embedded_terminal_gate_allows(
        connection,
        auth_enabled=identity.auth_enabled,
    )


def require_terminal_identity(
    request: Request,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
) -> RequestIdentity:
    if not connection_is_local_or_authenticated(request, identity):
        raise CoreApiError(
            403,
            "Embedded terminal is only available from local networks when authentication is not configured.",
        )
    return identity


@contextmanager
def profile_scope(profile: str | None) -> Iterator[None]:
    """Bind filesystem/config reads to the request's selected profile."""

    if not profile:
        yield
        return
    from api.profiles import clear_request_profile, set_request_profile

    set_request_profile(profile)
    try:
        yield
    finally:
        clear_request_profile()
