"""Profile-scoped secret metadata backed by the operating system credential vault."""

from datetime import UTC, datetime
from pathlib import Path
import re
from typing import Annotated, Literal
import uuid

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, ConfigDict, Field

from api.secret_vault import SecretVaultError, delete_secret as vault_delete, get_secret as vault_get, set_secret as vault_set
from ..dependencies import get_core_service
from ..profile_registry import mutate_json_list, read_json_list
from ..request_context import RequestIdentity, require_identity, require_mutation_identity
from ..services import AresCoreService


router = APIRouter(prefix="/api/secrets", tags=["secrets"])
KEY_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_.:-]{0,127}$")


def _secrets_file(profile: str | None) -> Path:
    from api.config import STATE_DIR
    safe = (profile or "default").replace("/", "_").replace("\\", "_")
    return STATE_DIR / f"secrets.{safe}.json"


class SecretEntry(BaseModel):
    id: str
    name: str = ""
    key: str
    value_preview: str | None = None
    provider: Literal["os_keychain"] = "os_keychain"
    status: Literal["active", "disabled", "archived"] = "active"
    description: str | None = None
    created_at: str
    updated_at: str


class SecretReveal(SecretEntry):
    value: str


class SecretCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    key: str = Field(min_length=1, max_length=128)
    value: str = Field(min_length=1, max_length=100_000)


class SecretUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str | None = Field(default=None, max_length=160)
    value: str | None = Field(default=None, min_length=1, max_length=100_000)
    description: str | None = Field(default=None, max_length=2_000)
    status: Literal["active", "disabled", "archived"] | None = None


class SecretDelete(BaseModel):
    model_config = ConfigDict(extra="forbid")
    key: str = Field(min_length=1, max_length=128)


def _preview(value: str) -> str:
    return f"••••{value[-4:]}" if value else "••••"


def _vault_error(exc: SecretVaultError) -> HTTPException:
    return HTTPException(status_code=503, detail=str(exc))


def _metadata(profile: str | None) -> list[dict]:
    """Migrate legacy plaintext values before returning metadata."""
    records = read_json_list(_secrets_file(profile))
    legacy = [(record, str(record.get("value") or "")) for record in records if record.get("value")]
    if not legacy:
        return records
    try:
        for record, value in legacy:
            vault_set(profile, str(record["key"]), value)
    except SecretVaultError as exc:
        raise _vault_error(exc) from exc

    def remove_plaintext(items: list[dict]) -> list[dict]:
        for item in items:
            value = str(item.pop("value", "") or "")
            item["provider"] = "os_keychain"
            if value:
                item["value_preview"] = _preview(value)
        return items
    return mutate_json_list(_secrets_file(profile), remove_plaintext)


def _public(record: dict) -> SecretEntry:
    clean = {key: value for key, value in record.items() if key != "value"}
    clean["provider"] = "os_keychain"
    return SecretEntry(**clean)


@router.get("", response_model=list[SecretEntry])
def list_secrets(identity: Annotated[RequestIdentity, Depends(require_identity)], service: Annotated[AresCoreService, Depends(get_core_service)]):
    return [_public(record) for record in _metadata(identity.profile)]


@router.get("/by-key/{key}", response_model=SecretReveal)
def reveal_secret(key: str, identity: Annotated[RequestIdentity, Depends(require_mutation_identity)], service: Annotated[AresCoreService, Depends(get_core_service)]):
    record = next((item for item in _metadata(identity.profile) if item.get("key") == key), None)
    if record is None:
        raise HTTPException(status_code=404, detail="Secret not found")
    try:
        value = vault_get(identity.profile, key)
    except SecretVaultError as exc:
        raise _vault_error(exc) from exc
    return SecretReveal(**_public(record).model_dump(), value=value)


@router.post("", response_model=SecretEntry)
def create_secret(payload: SecretCreate, identity: Annotated[RequestIdentity, Depends(require_mutation_identity)], service: Annotated[AresCoreService, Depends(get_core_service)]):
    key = payload.key.strip()
    if not KEY_PATTERN.fullmatch(key):
        raise HTTPException(status_code=400, detail="Secret keys must use letters, numbers, underscore, dot, colon, or hyphen.")
    try:
        vault_set(identity.profile, key, payload.value)
    except SecretVaultError as exc:
        raise _vault_error(exc) from exc
    now = datetime.now(UTC).isoformat()

    def upsert(items: list[dict]) -> dict:
        record = next((item for item in items if item.get("key") == key), None)
        if record is None:
            record = {"id": uuid.uuid4().hex[:12], "name": "", "key": key, "created_at": now}
            items.append(record)
        record.update(value_preview=_preview(payload.value), provider="os_keychain", status="active", updated_at=now)
        return record
    return _public(mutate_json_list(_secrets_file(identity.profile), upsert))


@router.patch("/{secret_id}", response_model=SecretEntry)
def update_secret(secret_id: str, update: SecretUpdate, identity: Annotated[RequestIdentity, Depends(require_mutation_identity)], service: Annotated[AresCoreService, Depends(get_core_service)]):
    current = next((item for item in _metadata(identity.profile) if item.get("id") == secret_id), None)
    if current is None:
        raise HTTPException(status_code=404, detail="Secret not found")
    values = update.model_dump(exclude_unset=True)
    value = values.pop("value", None)
    if value is not None:
        try:
            vault_set(identity.profile, str(current["key"]), value)
        except SecretVaultError as exc:
            raise _vault_error(exc) from exc

    def patch(items: list[dict]) -> dict:
        record = next(item for item in items if item.get("id") == secret_id)
        record.update(values)
        if value is not None:
            record["value_preview"] = _preview(value)
        record["updated_at"] = datetime.now(UTC).isoformat()
        return record
    return _public(mutate_json_list(_secrets_file(identity.profile), patch))


@router.delete("", response_model=list[SecretEntry])
def delete_secret(payload: SecretDelete, identity: Annotated[RequestIdentity, Depends(require_mutation_identity)], service: Annotated[AresCoreService, Depends(get_core_service)]):
    _metadata(identity.profile)
    try:
        vault_delete(identity.profile, payload.key)
    except SecretVaultError as exc:
        raise _vault_error(exc) from exc
    def delete(items: list[dict]) -> list[dict]:
        items[:] = [item for item in items if item.get("key") != payload.key]
        return items
    return [_public(record) for record in mutate_json_list(_secrets_file(identity.profile), delete)]
