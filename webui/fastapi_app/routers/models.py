"""Model catalog and main/auxiliary model selection."""

from __future__ import annotations

from typing import Annotated, Any, Literal

from fastapi import APIRouter, Depends, Query

from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_identity, require_mutation_identity


router = APIRouter(tags=["models"])


@router.get("/api/models")
def models(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    freshness: Literal["", "session_visit"] = Query(default=""),
):
    from api.config import get_available_models, get_available_models_for_session_visit
    from api.model_catalog import filter_catalog_for_active_backend

    with profile_scope(identity.profile):
        catalog = (
            get_available_models_for_session_visit()
            if freshness == "session_visit"
            else get_available_models()
        )
        return filter_catalog_for_active_backend(catalog)


@router.get("/api/models/live")
def live_models(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    provider: str = Query(default="", max_length=128),
):
    """Return a bounded provider model list without requiring a model runtime."""
    from api.live_models import get_live_models
    from api.profiles import profile_env_for_active_request

    with profile_scope(identity.profile):
        # Some provider discovery helpers still read process environment.
        # Mirror only for this bounded synchronous call, under the profile
        # module's serialization guard.
        with profile_env_for_active_request("/api/models/live"):
            return get_live_models(provider, profile=identity.profile)


@router.get("/api/reasoning")
def reasoning_status(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    model: str | None = Query(default=None, max_length=512),
    provider: str | None = Query(default=None, max_length=128),
    base_url: str | None = Query(default=None, max_length=4096),
):
    from api.config import get_reasoning_status

    with profile_scope(identity.profile):
        return get_reasoning_status(
            model_id=model,
            provider_id=provider,
            base_url=base_url,
        )


@router.post("/api/reasoning")
def update_reasoning(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.config import set_reasoning_display, set_reasoning_effort

    try:
        with profile_scope(identity.profile):
            if payload.get("display") is not None:
                display = str(payload.get("display") or "").strip().lower()
                if display in {"show", "on", "true", "1"}:
                    return set_reasoning_display(True)
                if display in {"hide", "off", "false", "0"}:
                    return set_reasoning_display(False)
                raise CoreApiError(400, "display must be show|hide|on|off")
            if payload.get("effort") is not None:
                return set_reasoning_effort(
                    payload.get("effort"),
                    model_id=str(payload.get("model") or "").strip() or None,
                    provider_id=str(payload.get("provider") or "").strip() or None,
                    base_url=str(payload.get("base_url") or "").strip() or None,
                )
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except RuntimeError as exc:
        raise CoreApiError(500, str(exc)) from exc
    raise CoreApiError(400, "reasoning: must supply 'display' or 'effort'")


@router.get("/api/model/auxiliary")
def auxiliary_models(identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.config import get_auxiliary_models

    with profile_scope(identity.profile):
        return get_auxiliary_models()


def _set_main(payload: dict[str, Any]):
    from api.config import set_ares_default_model
    from api.model_catalog import sync_main_model_to_jros

    provider = payload.get("provider")
    if str(provider or "").strip().lower() == "auto":
        provider = None
    result = set_ares_default_model(
        str(payload.get("model") or ""),
        provider=provider,
        advanced=payload.get("advanced"),
    )
    sync_main_model_to_jros(result)
    return result


@router.post("/api/default-model")
def default_model(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    try:
        with profile_scope(identity.profile):
            return _set_main(payload)
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except RuntimeError as exc:
        raise CoreApiError(500, str(exc)) from exc


@router.post("/api/model/set")
def set_model(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    scope = str(payload.get("scope") or "").strip()
    with profile_scope(identity.profile):
        if scope == "main":
            try:
                return _set_main(payload)
            except ValueError as exc:
                raise CoreApiError(400, str(exc)) from exc
        if scope == "auxiliary":
            from api.config import set_auxiliary_model

            try:
                return set_auxiliary_model(
                    str(payload.get("task") or "").strip(),
                    str(payload.get("provider") or "auto").strip(),
                    str(payload.get("model") or "").strip(),
                    advanced=payload.get("advanced"),
                )
            except Exception as exc:
                raise CoreApiError(400, str(exc)) from exc
    raise CoreApiError(400, f"unknown scope: {scope}")


__all__ = ["router"]
