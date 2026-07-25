"""Provider credentials, quota, cost, and cached model refresh contracts."""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query

from ..errors import CoreApiError
from ..request_context import (
    RequestIdentity,
    profile_scope,
    require_identity,
    require_mutation_identity,
)


router = APIRouter(tags=["providers"])


@router.get("/api/providers")
def providers(identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.profiles import profile_env_for_active_request_readonly
    from api.providers import get_providers

    with profile_scope(identity.profile):
        with profile_env_for_active_request_readonly("/api/providers"):
            return get_providers()


@router.post("/api/providers")
def set_provider(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.providers import set_provider_key

    provider = str(payload.get("provider") or "").strip().lower()
    if not provider:
        raise CoreApiError(400, "provider is required")
    api_key = payload.get("api_key")
    api_key = str(api_key).strip() or None if api_key is not None else None
    with profile_scope(identity.profile):
        result = set_provider_key(provider, api_key)
    if not result.get("ok"):
        raise CoreApiError(400, str(result.get("error") or "Unknown error"))
    return result


@router.post("/api/providers/delete")
def delete_provider(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.providers import remove_provider_key

    provider = str(payload.get("provider") or "").strip().lower()
    if not provider:
        raise CoreApiError(400, "provider is required")
    with profile_scope(identity.profile):
        result = remove_provider_key(provider)
    if not result.get("ok"):
        raise CoreApiError(400, str(result.get("error") or "Unknown error"))
    return result


@router.post("/api/providers/self-hosted")
def self_hosted_provider(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.onboarding import apply_self_hosted_provider_setup

    try:
        with profile_scope(identity.profile):
            return apply_self_hosted_provider_setup(payload)
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc


@router.get("/api/provider/quota")
def provider_quota(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    provider: str | None = None,
    refresh: bool = False,
):
    from api.profiles import profile_env_for_active_request_readonly
    from api.providers import get_provider_quota

    with profile_scope(identity.profile):
        with profile_env_for_active_request_readonly("/api/provider/quota"):
            return get_provider_quota(provider, refresh=refresh)


@router.get("/api/provider/cost-history")
def provider_cost_history(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    provider: str | None = None,
    days: int = Query(default=7, ge=1, le=365),
):
    from api.providers import get_provider_cost_history

    with profile_scope(identity.profile):
        return get_provider_cost_history(provider, days)


@router.post("/api/models/refresh")
def refresh_models(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.config import invalidate_provider_models_cache

    provider = str(payload.get("provider") or "").strip().lower()
    if not provider:
        raise CoreApiError(400, "provider is required")
    invalidate_provider_models_cache(provider)
    return {"ok": True, "provider": provider}


__all__ = ["router"]
