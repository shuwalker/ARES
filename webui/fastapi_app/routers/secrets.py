"""User-managed secrets.

Stored in the ARES state directory, scoped by profile. Not intended for
production multi-user deployments; this is the personal SI local store.
"""

import json
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from ..dependencies import get_core_service
from ..request_context import RequestIdentity, require_identity, require_mutation_identity
from ..services import AresCoreService

router = APIRouter(prefix="/api/secrets", tags=["secrets"])


def _secrets_file(profile: str | None) -> Path:
    from api.config import STATE_DIR
    safe = (profile or "default").replace("/", "_").replace("\\", "_")
    return STATE_DIR / f"secrets.{safe}.json"


def _load_secrets(profile: str | None) -> list[dict]:
    path = _secrets_file(profile)
    if not path.exists():
        return []
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        return []
    return data if isinstance(data, list) else []


def _save_secrets(profile: str | None, data: list[dict]) -> None:
    path = _secrets_file(profile)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)


class SecretEntry(BaseModel):
    id: str = Field(default_factory=lambda: uuid.uuid4().hex[:12])
    name: str = ""
    key: str
    value: str
    value_preview: str | None = None
    provider: str = "local_encrypted"
    status: str = "active"
    description: str | None = None
    created_at: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())
    updated_at: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())


class SecretUpdate(BaseModel):
    name: str | None = None
    key: str | None = None
    value: str | None = None
    description: str | None = None
    provider: str | None = None
    status: str | None = None


class SecretDelete(BaseModel):
    key: str


@router.get("", response_model=list[SecretEntry])
def list_secrets(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    return [SecretEntry(**s).model_dump() for s in _load_secrets(identity.profile)]


@router.get("/by-key/{key}", response_model=SecretEntry)
def get_secret_by_key(
    key: str,
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    data = _load_secrets(identity.profile)
    for s in data:
        if s.get("key") == key:
            return SecretEntry(**s)
    raise __import__("fastapi").HTTPException(status_code=404, detail="Secret not found")


@router.post("", response_model=SecretEntry)
def create_secret(
    entry: SecretEntry,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    data = _load_secrets(identity.profile)
    now = datetime.now(timezone.utc).isoformat()
    record = entry.model_dump()
    record["created_at"] = record.get("created_at") or now
    record["updated_at"] = now
    record["value_preview"] = record["value"][:8] if record.get("value") else None

    for i, s in enumerate(data):
        if s.get("key") == record["key"]:
            record["id"] = s["id"]
            record["created_at"] = s.get("created_at", record["created_at"])
            data[i] = record
            _save_secrets(identity.profile, data)
            return SecretEntry(**record)

    data.append(record)
    _save_secrets(identity.profile, data)
    return SecretEntry(**record)


@router.patch("/{secret_id}", response_model=SecretEntry)
def update_secret(
    secret_id: str,
    update: SecretUpdate,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    data = _load_secrets(identity.profile)
    for s in data:
        if s.get("id") == secret_id:
            for field, value in update.model_dump(exclude_none=True).items():
                s[field] = value
            s["updated_at"] = datetime.now(timezone.utc).isoformat()
            if "value" in update.model_dump(exclude_none=True):
                s["value_preview"] = (update.value or "")[:8]
            _save_secrets(identity.profile, data)
            return SecretEntry(**s)
    raise __import__("fastapi").HTTPException(status_code=404, detail="Secret not found")


@router.delete("", response_model=list[SecretEntry])
def delete_secret(
    payload: SecretDelete,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    data = _load_secrets(identity.profile)
    data = [s for s in data if s.get("key") != payload.key]
    _save_secrets(identity.profile, data)
    return [SecretEntry(**s).model_dump() for s in data]
