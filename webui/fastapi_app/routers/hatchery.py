"""ARES Hatchery API endpoints — hardware scan, personality molding, SI hatching."""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Request

from ..errors import CoreApiError
from ..request_context import RequestIdentity, require_identity, require_mutation_identity
from api.backends.ollama_hatchery import (
    scan_hardware, mold_si, hatch_si, get_hatchery_status, delete_si, update_si_personality,
)

router = APIRouter(prefix="/api/hatchery", tags=["hatchery"])


def _require_mutation(
    request: Request,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
) -> RequestIdentity:
    return identity


@router.get("/scan")
def scan(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    try:
        return scan_hardware()
    except Exception as exc:
        raise CoreApiError(500, f"Hardware scan failed: {exc}") from exc


@router.get("/status")
def status(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    try:
        return get_hatchery_status()
    except Exception as exc:
        raise CoreApiError(500, f"Failed to get hatchery status: {exc}") from exc


@router.post("/mold")
def mold(payload: dict[str, Any], _identity: Annotated[RequestIdentity, Depends(require_identity)]):
    try:
        return mold_si(
            name=str(payload.get("name") or "").strip(),
            base_model=str(payload.get("base_model") or "").strip(),
            system_prompt=str(payload.get("system_prompt") or ""),
            temperature=float(payload.get("temperature") or 0.7),
            top_p=float(payload.get("top_p") or 0.9),
            num_ctx=int(payload.get("num_ctx") or 32768),
            thinking=bool(payload.get("thinking", True)),
        )
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc


@router.post("/hatch")
def hatch(payload: dict[str, Any], _identity: Annotated[RequestIdentity, Depends(_require_mutation)]):
    try:
        return hatch_si(
            name=str(payload.get("name") or "").strip(),
            base_model=str(payload.get("base_model") or "").strip(),
            system_prompt=str(payload.get("system_prompt") or ""),
            temperature=float(payload.get("temperature") or 0.7),
            top_p=float(payload.get("top_p") or 0.9),
            num_ctx=int(payload.get("num_ctx") or 32768),
            thinking=bool(payload.get("thinking", True)),
            pull_if_missing=bool(payload.get("pull_if_missing", True)),
        )
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except RuntimeError as exc:
        raise CoreApiError(500, str(exc)) from exc


@router.post("/update")
def update(payload: dict[str, Any], _identity: Annotated[RequestIdentity, Depends(_require_mutation)]):
    name = str(payload.get("name") or "").strip()
    if not name:
        raise CoreApiError(400, "name is required")
    try:
        return update_si_personality(
            name=name,
            system_prompt=payload.get("system_prompt"),
            temperature=payload.get("temperature"),
            top_p=payload.get("top_p"),
            thinking=payload.get("thinking"),
        )
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except RuntimeError as exc:
        raise CoreApiError(500, str(exc)) from exc


@router.post("/delete")
def delete(payload: dict[str, Any], _identity: Annotated[RequestIdentity, Depends(_require_mutation)]):
    name = str(payload.get("name") or "").strip()
    if not name:
        raise CoreApiError(400, "name is required")
    try:
        return delete_si(name)
    except Exception as exc:
        raise CoreApiError(500, f"Failed to delete SI: {exc}") from exc