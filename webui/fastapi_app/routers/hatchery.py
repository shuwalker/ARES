"""ARES Hatchery API endpoints — hardware scan, personality molding, SI hatching.

These endpoints power the Hatchery UI flow:
  1. /api/hatchery/scan       — detect hardware, recommend local LLM
  2. /api/hatchery/status      — current hatchery state (hatched SIs, Ollama status)
  3. /api/hatchery/mold        — validate and preview a SI configuration
  4. /api/hatchery/hatch       — create the SI (Ollama model + birth certificate)
  5. /api/hatchery/update      — update personality/params of an existing SI
  6. /api/hatchery/delete      — remove a hatched SI
"""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Request

from ..errors import CoreApiError
from ..request_context import RequestIdentity, require_identity, require_mutation_identity
from api.backends.ollama_hatchery import (
    scan_hardware,
    mold_si,
    hatch_si,
    get_hatchery_status,
    delete_si,
    update_si_personality,
)

router = APIRouter(prefix="/api/hatchery", tags=["hatchery"])


def _require_mutation(
    request: Request,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
) -> RequestIdentity:
    return identity


@router.get("/scan")
def scan(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    """Scan hardware and recommend the best local LLM for hatching."""
    try:
        return scan_hardware()
    except Exception as exc:
        raise CoreApiError(500, f"Hardware scan failed: {exc}") from exc


@router.get("/status")
def status(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    """Get current hatchery status: hatched SIs, Ollama state, hardware."""
    try:
        return get_hatchery_status()
    except Exception as exc:
        raise CoreApiError(500, f"Failed to get hatchery status: {exc}") from exc


@router.post("/mold")
def mold(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    """Validate and preview a SI configuration before hatching.

    Payload:
      - name: SI name (lowercase, alphanumeric, hyphens)
      - base_model: Ollama model name (e.g. "qwen3.6:35b-mlx")
      - system_prompt: personality text (optional)
      - temperature: float 0.0-2.0 (default 0.7)
      - top_p: float 0.0-1.0 (default 0.9)
      - num_ctx: int context window (default 32768)
      - thinking: bool (default true)
    """
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
def hatch(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(_require_mutation)],
):
    """Hatch a Synthetic Intelligence: create Ollama model + birth certificate.

    Payload: same as /mold, plus:
      - pull_if_missing: bool (default true) — auto-pull the base model if not local
    """
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
def update(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(_require_mutation)],
):
    """Update a hatched SI's personality or parameters. Re-creates the Ollama model.

    Payload:
      - name: SI name to update (required)
      - system_prompt: new personality text (optional)
      - temperature: new temperature (optional)
      - top_p: new top_p (optional)
      - thinking: new thinking mode (optional)
    """
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
def delete(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(_require_mutation)],
):
    """Delete a hatched SI: remove from Ollama, delete birth certificate, unregister."""
    name = str(payload.get("name") or "").strip()
    if not name:
        raise CoreApiError(400, "name is required")
    try:
        return delete_si(name)
    except Exception as exc:
        raise CoreApiError(500, f"Failed to delete SI: {exc}") from exc


__all__ = ["router"]