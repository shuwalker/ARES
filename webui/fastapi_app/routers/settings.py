"""Local Profile settings endpoints."""

from typing import Annotated

from fastapi import APIRouter, Depends, Request, Response

from ..dependencies import get_core_service
from ..errors import CoreApiError
from ..request_context import (
    RequestIdentity,
    _set_auth_cookie,
    profile_scope,
    require_identity,
    require_mutation_identity,
)
from ..schemas import SettingsResponse, SettingsUpdate
from ..services import AresCoreService


router = APIRouter(prefix="/api/settings", tags=["settings"])


@router.get("", response_model=SettingsResponse)
def get_settings(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    return service.settings(profile=identity.profile)


@router.post("", response_model=SettingsResponse)
def update_settings(
    update: SettingsUpdate,
    request: Request,
    response: Response,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    # Preserve the explicit injected-service seam used by contract tests.
    if not isinstance(service, AresCoreService):
        return service.update_settings(update, profile=identity.profile)

    from api.network_trust import onboarding_gate_allows
    from api.settings_service import SettingsMutationError, update_local_profile_settings

    payload = update.model_dump(exclude_unset=True, by_alias=True)
    try:
        with profile_scope(identity.profile):
            saved, new_cookie = update_local_profile_settings(
                payload,
                session_cookie=identity.session_cookie,
                onboarding_allowed=onboarding_gate_allows(request, identity.auth_enabled),
            )
    except SettingsMutationError as exc:
        raise CoreApiError(exc.status_code, exc.message) from exc
    if new_cookie:
        _set_auth_cookie(response, request, new_cookie)
        response.headers["Cache-Control"] = "no-store"
    result = service.settings(profile=identity.profile)
    result.update(saved)
    return result
