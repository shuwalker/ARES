"""Password, trusted-header, OIDC, and passkey authentication contracts."""

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query, Request, Response
from fastapi.responses import RedirectResponse
from pydantic import BaseModel, ConfigDict, Field

from ..errors import CoreApiError
from ..request_context import (
    RequestIdentity,
    require_mutation_identity,
    resolve_request_identity,
)


router = APIRouter(tags=["authentication"])


class LoginRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    password: str = Field(max_length=4096)


def _set_session_cookie(request: Request, response: Response, cookie_value: str) -> None:
    from api.auth import (
        _resolve_cookie_name,
        _resolve_session_ttl,
    )

    response.set_cookie(
        _resolve_cookie_name(),
        cookie_value,
        httponly=True,
        secure=request.url.scheme == "https",
        samesite="lax",
        path="/",
        max_age=_resolve_session_ttl(),
    )


@router.get("/api/auth/status")
def auth_status(request: Request, response: Response):
    from api.auth import (
        _passkey_feature_flag_enabled,
        get_password_hash,
        is_auth_enabled,
        is_oidc_auth_enabled,
        is_trusted_auth_enabled,
    )
    from api.config import load_settings
    from api.passkeys import registered_credentials

    enabled = is_auth_enabled()
    identity = resolve_request_identity(request, response, allow_anonymous=True)
    passkey_flag = _passkey_feature_flag_enabled()
    passkeys = registered_credentials() if passkey_flag else []
    password_enabled = get_password_hash() is not None
    payload: dict[str, Any] = {
        "auth_enabled": enabled,
        "logged_in": not enabled or bool(identity.session_cookie),
        "password_auth_enabled": password_enabled,
        "oidc_enabled": is_oidc_auth_enabled(),
        "passwordless_enabled": bool(passkeys) and not password_enabled,
        "passkeys_enabled": bool(passkeys),
        "passkeys_count": len(passkeys),
        "passkey_feature_flag": passkey_flag,
        "auth_disabled_acknowledged": (
            bool(load_settings().get("auth_disabled_acknowledged")) if not enabled else False
        ),
    }
    if is_trusted_auth_enabled() or identity.auth_type == "trusted":
        payload["trusted_auth_enabled"] = True
    if identity.auth_type == "trusted":
        payload.update(
            {
                "auth_type": identity.auth_type,
                "user": identity.username,
                "bound_profile": identity.bound_profile,
            }
        )
    response.headers["Cache-Control"] = "no-store"
    return payload


@router.get("/api/auth/oidc/start")
def oidc_start(request: Request, next_path: str = Query(default="", alias="next")):
    from api.auth_oidc import OIDCAuthError, OIDCConfigError, build_authorization_redirect

    try:
        location = build_authorization_redirect(str(request.base_url).rstrip("/"), next_path)
    except OIDCConfigError as exc:
        raise CoreApiError(404, str(exc)) from exc
    except OIDCAuthError as exc:
        raise CoreApiError(exc.status_code, str(exc)) from exc
    return RedirectResponse(location, status_code=302, headers={"Cache-Control": "no-store"})


@router.get("/api/auth/oidc/callback")
def oidc_callback(
    request: Request,
    error: str = "",
    error_description: str = "",
    state: str = "",
    code: str = "",
):
    from api.auth import create_session
    from api.auth_oidc import OIDCAuthError, OIDCConfigError, complete_authorization_code_flow

    if error.strip():
        raise CoreApiError(401, error_description.strip() or error.strip())
    if not state.strip() or not code.strip():
        raise CoreApiError(400, "Missing OIDC callback state or code")
    try:
        result = complete_authorization_code_flow(
            str(request.base_url).rstrip("/"), state.strip(), code.strip()
        )
    except OIDCConfigError as exc:
        raise CoreApiError(404, str(exc)) from exc
    except OIDCAuthError as exc:
        raise CoreApiError(exc.status_code, str(exc)) from exc
    redirect = RedirectResponse(str(result.get("next_path") or "/"), status_code=302)
    redirect.headers["Cache-Control"] = "no-store"
    _set_session_cookie(request, redirect, create_session())
    return redirect


@router.post("/api/auth/login")
def login(request: Request, payload: LoginRequest, response: Response):
    from api.auth import (
        _check_login_rate,
        _clear_login_attempts,
        _record_login_attempt,
        create_session,
        is_auth_enabled,
        verify_password,
    )

    if not is_auth_enabled():
        return {"ok": True, "message": "Auth not enabled"}
    client_ip = str(getattr(request.client, "host", "") or "unknown")
    if not _check_login_rate(client_ip):
        raise CoreApiError(429, "Too many attempts. Try again in a minute.")
    if not verify_password(payload.password):
        _record_login_attempt(client_ip)
        raise CoreApiError(401, "Invalid password")
    _clear_login_attempts(client_ip)
    cookie_value = create_session()
    _set_session_cookie(request, response, cookie_value)
    response.headers["Cache-Control"] = "no-store"
    return {"ok": True}


@router.post("/api/auth/logout")
def logout(
    request: Request,
    response: Response,
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.auth import _resolve_cookie_name, get_trusted_auth_logout_url, invalidate_session
    from api.helpers import get_profile_cookie_name

    cookie_name = _resolve_cookie_name()
    cookie_value = request.cookies.get(cookie_name, "")
    if cookie_value:
        invalidate_session(cookie_value)
    response.delete_cookie(cookie_name, path="/", samesite="lax")
    response.delete_cookie(get_profile_cookie_name(), path="/", samesite="lax")
    response.headers["Cache-Control"] = "no-store"
    payload = {"ok": True}
    if _identity.auth_type == "trusted":
        logout_url = get_trusted_auth_logout_url()
        if logout_url:
            payload["trusted_logout_url"] = logout_url
    return payload


def _passkey_enabled() -> None:
    from api.auth import _passkey_feature_flag_enabled

    if not _passkey_feature_flag_enabled():
        raise CoreApiError(404, "Passkey support is disabled.")


def _registration_identity(request: Request, response: Response) -> RequestIdentity:
    from api.auth import CSRF_HEADER_NAME, is_auth_enabled, verify_csrf_token
    from api.network_trust import onboarding_gate_allows

    identity = resolve_request_identity(request, response, allow_anonymous=True)
    if not is_auth_enabled():
        if not onboarding_gate_allows(request, False):
            raise CoreApiError(401, "Authentication required")
        return identity
    if not identity.session_cookie:
        raise CoreApiError(401, "Authentication required")
    token = request.headers.get(CSRF_HEADER_NAME) or request.headers.get("X-CSRF-Token", "")
    if not verify_csrf_token(identity.session_cookie, token):
        raise CoreApiError(403, "Invalid CSRF token")
    return identity


@router.post("/api/auth/passkey/options")
def passkey_options(request: Request):
    from api.auth import is_auth_enabled
    from api.passkeys import PasskeyError, PasskeyRateLimitError, authentication_options

    _passkey_enabled()
    if not is_auth_enabled():
        raise CoreApiError(400, "Auth not enabled")
    try:
        return {"ok": True, "publicKey": authentication_options(request)}
    except PasskeyRateLimitError as exc:
        raise CoreApiError(429, str(exc)) from exc
    except PasskeyError as exc:
        raise CoreApiError(400, str(exc)) from exc


@router.post("/api/auth/passkey/login")
def passkey_login(request: Request, response: Response, payload: dict[str, Any]):
    from api.auth import (
        _check_login_rate,
        _record_login_attempt,
        create_session,
        is_auth_enabled,
    )
    from api.passkeys import PasskeyError, finish_login

    _passkey_enabled()
    if not is_auth_enabled():
        raise CoreApiError(400, "Auth not enabled")
    client_ip = str(getattr(request.client, "host", "") or "unknown")
    if not _check_login_rate(client_ip):
        raise CoreApiError(429, "Too many attempts. Try again in a minute.")
    try:
        finish_login(payload, request)
    except PasskeyError as exc:
        _record_login_attempt(client_ip)
        raise CoreApiError(401, str(exc)) from exc
    _set_session_cookie(request, response, create_session())
    response.headers["Cache-Control"] = "no-store"
    return {"ok": True}


@router.post("/api/auth/passkey/register/options")
def passkey_register_options(request: Request, response: Response):
    from api.passkeys import PasskeyError, PasskeyRateLimitError, registration_options

    _passkey_enabled()
    _registration_identity(request, response)
    try:
        return {"ok": True, "publicKey": registration_options(request)}
    except PasskeyRateLimitError as exc:
        raise CoreApiError(429, str(exc)) from exc
    except PasskeyError as exc:
        raise CoreApiError(400, str(exc)) from exc


@router.post("/api/auth/passkey/register")
def passkey_register(
    request: Request,
    response: Response,
    payload: dict[str, Any],
):
    from api.passkeys import PasskeyError, finish_registration, registered_credentials

    _passkey_enabled()
    _registration_identity(request, response)
    try:
        result = finish_registration(payload, request)
    except PasskeyError as exc:
        raise CoreApiError(400, str(exc)) from exc
    result["credentials"] = registered_credentials()
    return result


@router.post("/api/auth/passkey/delete")
def passkey_delete(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.auth import get_password_hash
    from api.passkeys import PasskeyError, delete_credential, registered_credentials

    _passkey_enabled()
    credential_id = str(payload.get("id") or "")
    credentials = registered_credentials()
    if (
        get_password_hash() is None
        and len(credentials) <= 1
        and any(item.get("id") == credential_id for item in credentials)
    ):
        raise CoreApiError(409, "Set a password or disable auth before removing the last passkey.")
    try:
        return delete_credential(credential_id)
    except PasskeyError as exc:
        raise CoreApiError(404, str(exc)) from exc


@router.post("/api/auth/passkeys")
def passkey_list(
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.auth import _passkey_feature_flag_enabled
    from api.passkeys import registered_credentials

    if not _passkey_feature_flag_enabled():
        return {"credentials": [], "disabled": True}
    return {"credentials": registered_credentials()}


__all__ = ["router"]
