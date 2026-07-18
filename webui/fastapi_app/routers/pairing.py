"""Pairing / device approval endpoints for ARES adapters.

Personal SI local store. Stored in the ARES state directory, scoped by profile.
"""

import json
import uuid
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from ..dependencies import get_core_service
from ..request_context import RequestIdentity, require_identity, require_mutation_identity
from ..services import AresCoreService

router = APIRouter(prefix="/api/connections/pairing", tags=["pairing"])


def _pairing_file(profile: str | None) -> Path:
    from api.config import STATE_DIR
    safe = (profile or "default").replace("/", "_").replace("\\", "_")
    return STATE_DIR / f"pairing.{safe}.json"


def _load_pairing(profile: str | None) -> list[dict]:
    path = _pairing_file(profile)
    if not path.exists():
        return []
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        return []
    return data if isinstance(data, list) else []


def _save_pairing(profile: str | None, data: list[dict]) -> None:
    path = _pairing_file(profile)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)


class PairingRequest(BaseModel):
    id: str = Field(default_factory=lambda: uuid.uuid4().hex[:12])
    name: str
    kind: str = "device"
    status: str = "pending"  # pending, approved, revoked
    created_at: str = Field(default_factory=lambda: __import__("datetime").datetime.utcnow().isoformat())


class PairingAction(BaseModel):
    id: str


@router.get("", response_model=list[PairingRequest])
def list_pairing(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    return _load_pairing(identity.profile)


@router.post("/create", response_model=PairingRequest)
def create_pairing(
    req: PairingRequest,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    data = _load_pairing(identity.profile)
    data.append(req.model_dump())
    _save_pairing(identity.profile, data)
    return req


@router.post("/approve", response_model=list[PairingRequest])
def approve_pairing(
    action: PairingAction,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    data = _load_pairing(identity.profile)
    for p in data:
        if p.get("id") == action.id:
            p["status"] = "approved"
    _save_pairing(identity.profile, data)
    return data


@router.post("/revoke", response_model=list[PairingRequest])
def revoke_pairing(
    action: PairingAction,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    data = _load_pairing(identity.profile)
    for p in data:
        if p.get("id") == action.id:
            p["status"] = "revoked"
    _save_pairing(identity.profile, data)
    return data


@router.post("/clear", response_model=list[PairingRequest])
def clear_pairing(
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    _save_pairing(identity.profile, [])
    return []
