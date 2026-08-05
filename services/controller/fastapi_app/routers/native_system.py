"""Native ARES application settings and lifecycle bridge."""

from typing import Annotated, Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict, Field

from ..errors import CoreApiError
from ..request_context import RequestIdentity, require_identity, require_mutation_identity


router = APIRouter(prefix="/api/system/native", tags=["system", "settings"])


class NativeSystemSettingsPatch(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    menu_bar_enabled: bool | None = None
    launch_at_login: bool | None = None
    quick_launch_enabled: bool | None = None
    quick_launch_shortcut: str | None = Field(default=None, min_length=1, max_length=80)
    background_operation: bool | None = None


class NativeActionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    action: Literal["restart_server"]


def _raise_contract_error(exc: Exception) -> None:
    from api.native_system import NativeSystemContractError

    if isinstance(exc, NativeSystemContractError):
        raise CoreApiError(exc.status_code, exc.message) from exc
    raise exc


@router.get("")
def get_native_system(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    from api.native_system import native_system_status

    return native_system_status()


@router.patch("/settings")
def patch_native_system_settings(
    update: NativeSystemSettingsPatch,
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.native_system import update_native_settings

    try:
        return update_native_settings(update.model_dump(exclude_unset=True))
    except Exception as exc:
        _raise_contract_error(exc)


@router.post("/actions")
def run_native_system_action(
    request: NativeActionRequest,
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.native_system import enqueue_native_action

    try:
        return enqueue_native_action(request.action)
    except Exception as exc:
        _raise_contract_error(exc)
