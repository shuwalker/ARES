"""Webhook registry for ARES gateway integrations.

Personal SI local registry. Stored in the ARES state directory, scoped by profile.
"""

import json
from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from ..dependencies import get_core_service
from ..request_context import RequestIdentity, require_identity, require_mutation_identity
from ..services import AresCoreService

router = APIRouter(prefix="/api/gateway/webhooks", tags=["webhooks"])


def _webhooks_file(profile: str | None) -> Path:
    from api.config import STATE_DIR
    safe = (profile or "default").replace("/", "_").replace("\\", "_")
    return STATE_DIR / f"webhooks.{safe}.json"


def _load_webhooks(profile: str | None) -> list[dict]:
    path = _webhooks_file(profile)
    if not path.exists():
        return []
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except (json.JSONDecodeError, OSError):
        return []
    return data if isinstance(data, list) else []


def _save_webhooks(profile: str | None, data: list[dict]) -> None:
    path = _webhooks_file(profile)
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)


class WebhookEntry(BaseModel):
    id: str = Field(default_factory=lambda: __import__("uuid").uuid4().hex[:12])
    name: str
    url: str
    event: str = "*"
    enabled: bool = True
    secret: str | None = None


class WebhookDelete(BaseModel):
    id: str


@router.get("", response_model=list[WebhookEntry])
def list_webhooks(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    return _load_webhooks(identity.profile)


@router.post("", response_model=WebhookEntry)
def create_webhook(
    entry: WebhookEntry,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    data = _load_webhooks(identity.profile)
    data.append(entry.model_dump())
    _save_webhooks(identity.profile, data)
    return entry


@router.delete("", response_model=list[WebhookEntry])
def delete_webhook(
    payload: WebhookDelete,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    data = _load_webhooks(identity.profile)
    data = [w for w in data if w.get("id") != payload.id]
    _save_webhooks(identity.profile, data)
    return data


@router.patch("/{webhook_id}", response_model=WebhookEntry)
def update_webhook(
    webhook_id: str,
    update: WebhookEntry,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    data = _load_webhooks(identity.profile)
    for w in data:
        if w.get("id") == webhook_id:
            w["enabled"] = update.enabled
            _save_webhooks(identity.profile, data)
            return WebhookEntry(**w)
    raise __import__("fastapi").HTTPException(status_code=404, detail="Webhook not found")
