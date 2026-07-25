"""Environment variable editor backend.

Personal SI local store. Stored in the ARES state directory, scoped by profile.
Mirrors the secrets store but uses a separate file and exposes a reveal endpoint.
"""

import json
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from ..dependencies import get_core_service
from ..request_context import RequestIdentity, require_identity, require_mutation_identity
from ..services import AresCoreService

router = APIRouter(prefix="/api/env", tags=["env"])


def _env_file(profile: str | None) -> Path:
    from api.config import STATE_DIR
    safe = (profile or "default").replace("/", "_").replace("\\", "_")
    return STATE_DIR / f"env.{safe}.json"


def _load_env(profile: str | None) -> dict:
    path = _env_file(profile)
    if not path.exists():
        return {"variables": {}, "order": []}
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        return {"variables": {}, "order": []}
    if not isinstance(data, dict):
        return {"variables": {}, "order": []}
    data.setdefault("variables", {})
    data.setdefault("order", [])
    return data


def _save_env(profile: str | None, data: dict) -> None:
    path = _env_file(profile)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)


class EnvResponse(BaseModel):
    variables: dict[str, str] = Field(default_factory=dict)
    order: list[str] = Field(default_factory=list)


class EnvUpdate(BaseModel):
    key: str
    value: str


class EnvDelete(BaseModel):
    key: str


@router.get("", response_model=EnvResponse)
def get_env(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    data = _load_env(identity.profile)
    return EnvResponse(variables=data["variables"], order=data["order"])


@router.get("/{key}/reveal")
def reveal_env(
    key: str,
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    data = _load_env(identity.profile)
    return {"key": key, "value": data["variables"].get(key, "")}


@router.post("", response_model=EnvResponse)
def upsert_env(
    update: EnvUpdate,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    data = _load_env(identity.profile)
    data["variables"][update.key] = update.value
    if update.key not in data["order"]:
        data["order"].append(update.key)
    _save_env(identity.profile, data)
    return EnvResponse(variables=data["variables"], order=data["order"])


@router.delete("", response_model=EnvResponse)
def delete_env(
    payload: EnvDelete,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    data = _load_env(identity.profile)
    data["variables"].pop(payload.key, None)
    data["order"] = [k for k in data["order"] if k != payload.key]
    _save_env(identity.profile, data)
    return EnvResponse(variables=data["variables"], order=data["order"])


@router.post("/reorder", response_model=EnvResponse)
def reorder_env(
    order: list[str],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    data = _load_env(identity.profile)
    existing = set(data["variables"].keys())
    data["order"] = [k for k in order if k in existing] + [k for k in existing if k not in order]
    _save_env(identity.profile, data)
    return EnvResponse(variables=data["variables"], order=data["order"])
