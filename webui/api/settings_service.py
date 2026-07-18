"""Transport-neutral Local Profile settings mutation policy."""

from __future__ import annotations

from dataclasses import dataclass
import os
from typing import Any


@dataclass
class SettingsMutationError(Exception):
    status_code: int
    message: str

    def __str__(self) -> str:
        return self.message


def update_local_profile_settings(
    payload: dict[str, Any],
    *,
    session_cookie: str | None,
    onboarding_allowed: bool,
) -> tuple[dict[str, Any], str | None]:
    from api.auth import (
        create_session,
        get_password_hash,
        is_auth_enabled,
        verify_password,
        verify_session,
    )
    from api.config import (
        get_max_tokens_status,
        persisted_speech_settings_keys,
        save_settings,
        set_max_tokens,
    )

    body = dict(payload)
    if "bot_name" in body:
        body["bot_name"] = str(body["bot_name"] or "").strip() or "Ares"
    auth_before = is_auth_enabled()
    password_before = auth_before and get_password_hash() is not None
    logged_in_before = bool(session_cookie and verify_session(session_cookie))
    requested_password = bool(
        isinstance(body.get("_set_password"), str)
        and str(body.get("_set_password") or "").strip()
    )
    requested_passwordless = bool(body.pop("_passwordless", False))
    requested_clear = bool(body.get("_clear_password") or requested_passwordless)
    if requested_passwordless:
        body["_clear_password"] = True
    current_password = body.pop("_current_password", None)

    if (requested_password or requested_clear) and os.getenv("ARES_WEBUI_PASSWORD", "").strip():
        raise SettingsMutationError(
            409,
            "ARES_WEBUI_PASSWORD is set and overrides the Local Profile password. "
            "Unset it and restart ARES before changing password authentication here.",
        )
    if requested_password and not auth_before and not onboarding_allowed:
        raise SettingsMutationError(
            403,
            "First password setup is only available from local networks when authentication is not enabled.",
        )
    if auth_before and password_before and (requested_password or requested_clear):
        if not isinstance(current_password, str) or not current_password:
            raise SettingsMutationError(403, "Current password is required to change or disable authentication.")
        if not verify_password(current_password):
            raise SettingsMutationError(403, "Current password is incorrect.")

    if requested_passwordless:
        from api.auth import _passkey_feature_flag_enabled
        from api.passkeys import registered_credentials

        if not _passkey_feature_flag_enabled():
            raise SettingsMutationError(409, "Passkey support must be enabled before going passwordless.")
        if not registered_credentials():
            raise SettingsMutationError(409, "Register a passkey before going passwordless.")
    elif requested_clear:
        from api.passkeys import clear_credentials

        clear_credentials()

    acknowledged = body.pop("_auth_disabled_acknowledged", None)
    if acknowledged is not None and not is_auth_enabled():
        body["auth_disabled_acknowledged"] = bool(acknowledged)
    elif is_auth_enabled() or requested_password:
        body["auth_disabled_acknowledged"] = False

    max_tokens_provided = "max_tokens" in body
    max_tokens_value = body.pop("max_tokens", None) if max_tokens_provided else None
    saved = save_settings(body)
    saved["persisted_speech_keys"] = persisted_speech_settings_keys()
    saved.pop("password_hash", None)
    saved.update(
        set_max_tokens(max_tokens_value)
        if max_tokens_provided
        else get_max_tokens_status()
    )

    if any(
        key in body
        for key in (
            "show_cli_sessions",
            "show_claude_code_sessions",
            "show_cron_sessions",
            "show_webhook_sessions",
            "show_previous_messaging_sessions",
        )
    ):
        try:
            from api.route_session_list_cache import _clear_session_list_cache

            _clear_session_list_cache()
        except Exception:
            pass
        try:
            from api.models import clear_cli_sessions_cache

            clear_cli_sessions_cache()
        except Exception:
            pass

    auth_after = is_auth_enabled()
    auth_just_enabled = bool(requested_password and auth_after and not auth_before)
    new_cookie = create_session() if auth_just_enabled and not logged_in_before else None
    saved.update(
        auth_enabled=auth_after,
        password_auth_enabled=get_password_hash() is not None,
        logged_in=logged_in_before or bool(new_cookie),
        auth_just_enabled=auth_just_enabled,
    )
    try:
        from api.auth import _passkey_feature_flag_enabled
        from api.passkeys import registered_credentials

        credentials = registered_credentials() if _passkey_feature_flag_enabled() else []
        saved["passkeys_enabled"] = bool(credentials)
        saved["passwordless_enabled"] = bool(credentials) and not saved["password_auth_enabled"]
    except Exception:
        pass
    return saved, new_cookie
