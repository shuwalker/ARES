"""Local Profile discovery, selection, creation, and deletion."""

from __future__ import annotations

import re
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Response

from ..errors import CoreApiError
from ..request_context import (
    RequestIdentity,
    profile_scope,
    require_identity,
    require_mutation_identity,
)


router = APIRouter(tags=["profiles"])
_PROFILE_INPUT = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")


@router.get("/api/profiles")
def profiles(identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api import profiles as profiles_api

    with profile_scope(identity.profile):
        return {
            "profiles": profiles_api.list_profiles_api(),
            "active": profiles_api.get_active_profile_name(),
            "single_profile_mode": profiles_api._is_isolated_profile_mode(),
        }


@router.get("/api/profile/active")
def active_profile(identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api import profiles as profiles_api
    from api.workspace import get_profile_default_workspace

    with profile_scope(identity.profile):
        name = profiles_api.get_active_profile_name()
        try:
            workspace = get_profile_default_workspace()
        except Exception:
            workspace = None
        return {
            "name": name,
            "path": str(profiles_api.get_active_ares_home()),
            "is_default": profiles_api._is_root_profile(name),
            "default_workspace": workspace,
        }


@router.post("/api/profile/switch")
def switch_profile(
    payload: dict[str, Any],
    response: Response,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.config import invalidate_models_cache
    from api.helpers import build_profile_cookie, get_profile_cookie_name
    from api.profiles import _validate_profile_name, switch_profile as switch

    name = str(payload.get("name") or "").strip()
    if not name:
        raise CoreApiError(400, "name is required")
    if identity.bound_profile and name != identity.bound_profile:
        raise CoreApiError(403, "Profile is bound to the current session")
    try:
        if name != "default":
            _validate_profile_name(name)
        result = switch(name, process_wide=False)
        invalidate_models_cache()
        try:
            from api.gateway_watcher import restart_watcher_for_profile

            restart_watcher_for_profile(name)
        except Exception:
            pass
        if identity.session_cookie:
            response.headers.append(
                "set-cookie",
                build_profile_cookie(name, session_cookie_value=identity.session_cookie),
            )
        else:
            response.set_cookie(
                get_profile_cookie_name(),
                name,
                httponly=True,
                samesite="lax",
                path="/",
            )
        return result
    except PermissionError as exc:
        raise CoreApiError(403, str(exc)) from exc
    except (ValueError, FileNotFoundError) as exc:
        raise CoreApiError(404, str(exc)) from exc
    except RuntimeError as exc:
        raise CoreApiError(409, str(exc)) from exc


@router.post("/api/profile/create")
def create_profile(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.profiles import create_profile_api

    name = str(payload.get("name") or "").strip()
    if not name:
        raise CoreApiError(400, "name is required")
    if not _PROFILE_INPUT.fullmatch(name):
        raise CoreApiError(
            400,
            "Invalid profile name: lowercase letters, numbers, hyphens, underscores only",
        )
    clone_from = payload.get("clone_from")
    if clone_from is not None:
        clone_from = str(clone_from).strip()
        if not _PROFILE_INPUT.fullmatch(clone_from):
            raise CoreApiError(400, "Invalid clone_from name")
    base_url = str(payload.get("base_url") or "").strip() or None
    if base_url and not base_url.startswith(("http://", "https://")):
        raise CoreApiError(400, "base_url must start with http:// or https://")
    try:
        profile = create_profile_api(
            name,
            clone_from=clone_from,
            clone_config=bool(payload.get("clone_config", False)),
            base_url=base_url,
            api_key=str(payload.get("api_key") or "").strip() or None,
            default_model=str(payload.get("default_model") or "").strip() or None,
            model_provider=str(payload.get("model_provider") or "").strip() or None,
        )
    except PermissionError as exc:
        raise CoreApiError(403, str(exc)) from exc
    except (ValueError, FileExistsError, RuntimeError) as exc:
        raise CoreApiError(400, str(exc)) from exc
    return {"ok": True, "profile": profile}


@router.post("/api/profile/delete")
def delete_profile(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.profiles import _validate_profile_name, delete_profile_api

    name = str(payload.get("name") or "").strip()
    if not name:
        raise CoreApiError(400, "name is required")
    try:
        _validate_profile_name(name)
        return delete_profile_api(name)
    except PermissionError as exc:
        raise CoreApiError(403, str(exc)) from exc
    except (ValueError, FileNotFoundError) as exc:
        raise CoreApiError(400, str(exc)) from exc
    except RuntimeError as exc:
        raise CoreApiError(409, str(exc)) from exc


__all__ = ["router"]
