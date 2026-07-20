"""Pairing / device approval endpoints for ARES adapters.

Personal SI local store. Stored in the ARES state directory, scoped by profile.
"""

import uuid
from datetime import UTC, datetime
from pathlib import Path
from typing import Annotated, Literal

from fastapi import APIRouter, Depends
from pydantic import BaseModel, ConfigDict, Field

from ..dependencies import get_core_service
from ..request_context import RequestIdentity, require_identity, require_mutation_identity
from ..services import AresCoreService
from ..profile_registry import mutate_json_list, read_json_list

router = APIRouter(prefix="/api/connections/pairing", tags=["pairing"])


def _pairing_file(profile: str | None) -> Path:
    from api.config import STATE_DIR
    safe = (profile or "default").replace("/", "_").replace("\\", "_")
    return STATE_DIR / f"pairing.{safe}.json"


def _load_pairing(profile: str | None) -> list[dict]:
    return read_json_list(_pairing_file(profile))


class PairingRequest(BaseModel):
    id: str = Field(default_factory=lambda: uuid.uuid4().hex[:12])
    name: str
    kind: str = "device"
    status: Literal["pending", "approved", "revoked"] = "pending"
    created_at: str = Field(default_factory=lambda: datetime.now(UTC).isoformat())


class PairingAction(BaseModel):
    id: str


class PairingCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    name: str = Field(min_length=1, max_length=120)
    kind: str = Field(default="device", min_length=1, max_length=64)


@router.get("", response_model=list[PairingRequest])
def list_pairing(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    return _load_pairing(identity.profile)


@router.post("/create", response_model=PairingRequest)
def create_pairing(
    req: PairingCreate,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    pairing = PairingRequest(name=req.name, kind=req.kind)
    mutate_json_list(_pairing_file(identity.profile), lambda data: data.append(pairing.model_dump()))
    return pairing


@router.post("/approve", response_model=list[PairingRequest])
def approve_pairing(
    action: PairingAction,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    def approve(data: list[dict]) -> list[dict]:
        for pairing in data:
            if pairing.get("id") == action.id:
                pairing["status"] = "approved"
        return data
    return mutate_json_list(_pairing_file(identity.profile), approve)


@router.post("/revoke", response_model=list[PairingRequest])
def revoke_pairing(
    action: PairingAction,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    def revoke(data: list[dict]) -> list[dict]:
        for pairing in data:
            if pairing.get("id") == action.id:
                pairing["status"] = "revoked"
        return data
    return mutate_json_list(_pairing_file(identity.profile), revoke)


@router.post("/clear", response_model=list[PairingRequest])
def clear_pairing(
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    def clear_pending(data: list[dict]) -> list[dict]:
        data[:] = [pairing for pairing in data if pairing.get("status") != "pending"]
        return data
    return mutate_json_list(_pairing_file(identity.profile), clear_pending)
