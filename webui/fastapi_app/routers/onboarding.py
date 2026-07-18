"""Local Profile onboarding, credential probes, and optional runtime setup."""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query, Request

from ..errors import CoreApiError
from ..request_context import RequestIdentity, require_identity, require_mutation_identity


router = APIRouter(prefix="/api/onboarding", tags=["onboarding"])


def require_onboarding_mutation(
    request: Request,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
) -> RequestIdentity:
    from api.network_trust import onboarding_gate_allows

    if not onboarding_gate_allows(request, identity.auth_enabled):
        raise CoreApiError(
            403,
            "Onboarding is only available from local networks when authentication is not enabled. "
            "Set ARES_WEBUI_ONBOARDING_OPEN=1 only when another trusted network layer protects ARES.",
        )
    return identity


@router.get("/status")
def status(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.onboarding import get_onboarding_status

    return get_onboarding_status()


@router.get("/oauth/poll")
def oauth_poll(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    flow_id: str = Query(default=""),
):
    from api.onboarding_oauth import poll_onboarding_oauth_flow

    try:
        return poll_onboarding_oauth_flow(flow_id)
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except KeyError as exc:
        raise CoreApiError(404, str(exc)) from exc


@router.post("/oauth/start")
def oauth_start(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_onboarding_mutation)],
):
    from api.onboarding_oauth import start_onboarding_oauth_flow

    try:
        return start_onboarding_oauth_flow(payload)
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except RuntimeError as exc:
        raise CoreApiError(500, str(exc)) from exc


@router.post("/oauth/cancel")
def oauth_cancel(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_onboarding_mutation)],
):
    from api.onboarding_oauth import cancel_onboarding_oauth_flow

    try:
        return cancel_onboarding_oauth_flow(payload)
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc


@router.post("/setup")
def setup(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_onboarding_mutation)],
):
    from api.onboarding import apply_onboarding_setup

    try:
        return apply_onboarding_setup(payload)
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except RuntimeError as exc:
        raise CoreApiError(500, str(exc)) from exc


@router.get("/companion/ares-tools")
def companion_tools_status(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    from api.config import get_config
    from api.jros_ares_mcp import ares_mcp_available

    try:
        enabled = bool(get_config().get("jros_ares_tools_enabled"))
    except Exception:
        enabled = False
    return {"available": ares_mcp_available(), "enabled": enabled}


@router.post("/companion/ares-tools")
def companion_tools_update(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_onboarding_mutation)],
):
    from api.jros_ares_mcp import set_ares_tools_enabled

    try:
        return set_ares_tools_enabled(bool(payload.get("enabled", True)))
    except RuntimeError as exc:
        raise CoreApiError(500, str(exc)) from exc


@router.get("/companion/defaults")
def companion_defaults(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    from api.jros_companion import companion_available, companion_setup_defaults, list_characters

    if not companion_available():
        return {"available": False}
    try:
        return {
            "available": True,
            **companion_setup_defaults(),
            "characters": list_characters(),
        }
    except Exception as exc:
        raise CoreApiError(500, f"companion defaults failed: {exc}") from exc


@router.post("/companion/create")
def companion_create(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_onboarding_mutation)],
):
    from api.jros_companion import create_companion

    display_name = str(payload.get("display_name") or "").strip() or None
    try:
        result = create_companion(
            character_id=str(payload.get("character_id") or ""),
            name=str(payload.get("name") or "").strip() or None,
            display_name=display_name,
            personality=str(payload.get("personality") or "").strip() or None,
            voice_id=str(payload.get("voice_id") or "").strip() or None,
            permission_mode=str(payload.get("permission_mode") or "confirm").strip() or "confirm",
            make_default=bool(payload.get("make_default", True)),
        )
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except RuntimeError as exc:
        raise CoreApiError(500, str(exc)) from exc
    if display_name:
        try:
            from api.config import load_settings, save_settings

            save_settings({**(load_settings() or {}), "bot_name": display_name})
        except Exception:
            pass
    return result


@router.post("/jros/install")
def jros_install(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_onboarding_mutation)],
):
    from api.jros_companion import install_jros_if_missing

    try:
        return install_jros_if_missing(
            jaeger_home=str(payload.get("jaeger_home") or "").strip() or None,
        )
    except Exception as exc:
        raise CoreApiError(500, f"JROS install failed: {exc}") from exc


@router.post("/complete")
def complete(
    _identity: Annotated[RequestIdentity, Depends(require_onboarding_mutation)],
):
    from api.onboarding import complete_onboarding

    return complete_onboarding()


@router.post("/probe")
def probe(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_onboarding_mutation)],
):
    from api.onboarding import probe_provider_endpoint

    try:
        return probe_provider_endpoint(
            str(payload.get("provider") or "").strip().lower(),
            str(payload.get("base_url") or ""),
            str(payload.get("api_key") or "").strip() or None,
        )
    except Exception as exc:
        raise CoreApiError(500, f"probe failed: {exc}") from exc


__all__ = ["router"]
