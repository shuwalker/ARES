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

from typing import Annotated

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel, ConfigDict, Field, field_validator

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


class MoldRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    name: str = Field(min_length=1, max_length=64, pattern=r"^[a-z0-9][a-z0-9._-]{0,63}$")
    base_model: str = Field(min_length=1, max_length=256)
    system_prompt: str = Field(default="", max_length=100_000)
    temperature: float = Field(default=0.7, ge=0, le=2)
    top_p: float = Field(default=0.9, ge=0, le=1)
    num_ctx: int = Field(default=32768, ge=2048, le=131072)
    thinking: bool = True

    @field_validator("base_model")
    @classmethod
    def validate_base_model(cls, value: str) -> str:
        import re

        value = value.strip()
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._/:-]{0,255}", value):
            raise ValueError("base_model contains unsupported characters")
        return value


class HatchRequest(MoldRequest):
    pull_if_missing: bool = False


class UpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    name: str = Field(min_length=1, max_length=64, pattern=r"^[a-z0-9][a-z0-9._-]{0,63}$")
    system_prompt: str | None = Field(default=None, max_length=100_000)
    temperature: float | None = Field(default=None, ge=0, le=2)
    top_p: float | None = Field(default=None, ge=0, le=1)
    thinking: bool | None = None


class NameRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)

    name: str = Field(min_length=1, max_length=64, pattern=r"^[a-z0-9][a-z0-9._-]{0,63}$")


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
    payload: MoldRequest,
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
        return mold_si(**payload.model_dump())
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc


@router.post("/hatch")
def hatch(
    payload: HatchRequest,
    _identity: Annotated[RequestIdentity, Depends(_require_mutation)],
):
    """Hatch a Synthetic Intelligence: create Ollama model + birth certificate.

    Payload: same as /mold, plus:
      - pull_if_missing: bool (default false) — pull only after explicit user consent
    """
    try:
        return hatch_si(**payload.model_dump())
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except RuntimeError as exc:
        raise CoreApiError(500, str(exc)) from exc


@router.post("/update")
def update(
    payload: UpdateRequest,
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
    try:
        return update_si_personality(**payload.model_dump())
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except RuntimeError as exc:
        raise CoreApiError(500, str(exc)) from exc


@router.post("/delete")
def delete(
    payload: NameRequest,
    _identity: Annotated[RequestIdentity, Depends(_require_mutation)],
):
    """Delete a hatched SI: remove from Ollama, delete birth certificate, unregister."""
    try:
        return delete_si(payload.name)
    except Exception as exc:
        raise CoreApiError(500, f"Failed to delete SI: {exc}") from exc


__all__ = ["router"]
