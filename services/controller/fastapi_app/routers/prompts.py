"""Reusable prompt API backed by the selected Local Profile."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends

from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_identity, require_mutation_identity
from ..schemas import SavedPromptCreate, SavedPromptDelete


router = APIRouter(prefix="/api/prompts", tags=["prompts"])


@router.get("")
def list_prompts(identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.saved_prompts import load_saved_prompts

    with profile_scope(identity.profile):
        return {"prompts": load_saved_prompts()}


@router.post("")
def create_prompt(
    payload: SavedPromptCreate,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.saved_prompts import SavedPromptError, create_saved_prompt

    try:
        with profile_scope(identity.profile):
            prompt = create_saved_prompt(payload.text, payload.label)
    except SavedPromptError as exc:
        raise CoreApiError(400, str(exc)) from exc
    return {"ok": True, "prompt": prompt}


@router.delete("")
def delete_prompt(
    payload: SavedPromptDelete,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.saved_prompts import SavedPromptError, delete_saved_prompt

    try:
        with profile_scope(identity.profile):
            delete_saved_prompt(payload.id)
    except SavedPromptError as exc:
        raise CoreApiError(400, str(exc)) from exc
    return {"ok": True}


__all__ = ["router"]
