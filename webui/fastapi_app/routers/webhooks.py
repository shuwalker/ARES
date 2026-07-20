"""Webhook registry for ARES gateway integrations.

Personal SI local registry. Stored in the ARES state directory, scoped by profile.
"""

from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field

from ..dependencies import get_core_service
from ..request_context import RequestIdentity, require_identity, require_mutation_identity
from ..services import AresCoreService
from ..profile_registry import mutate_json_list, read_json_list

router = APIRouter(prefix="/api/gateway/webhooks", tags=["webhooks"])


def _webhooks_file(profile: str | None) -> Path:
    from api.config import STATE_DIR
    safe = (profile or "default").replace("/", "_").replace("\\", "_")
    return STATE_DIR / f"webhooks.{safe}.json"


def _load_webhooks(profile: str | None) -> list[dict]:
    return read_json_list(_webhooks_file(profile))


class WebhookEntry(BaseModel):
    id: str = Field(default_factory=lambda: __import__("uuid").uuid4().hex[:12])
    name: str
    url: str
    event: str = "*"
    enabled: bool = True
    secret: str | None = None


class WebhookDelete(BaseModel):
    id: str


class WebhookUpdate(BaseModel):
    name: str | None = None
    url: str | None = None
    event: str | None = None
    enabled: bool | None = None
    secret: str | None = None


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
    mutate_json_list(_webhooks_file(identity.profile), lambda data: data.append(entry.model_dump()))
    return entry


@router.delete("", response_model=list[WebhookEntry])
def delete_webhook(
    payload: WebhookDelete,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    def delete(data: list[dict]) -> list[dict]:
        data[:] = [webhook for webhook in data if webhook.get("id") != payload.id]
        return data
    return mutate_json_list(_webhooks_file(identity.profile), delete)


@router.patch("/{webhook_id}", response_model=WebhookEntry)
def update_webhook(
    webhook_id: str,
    update: WebhookUpdate,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    def patch(data: list[dict]) -> WebhookEntry:
        for webhook in data:
            if webhook.get("id") == webhook_id:
                webhook.update(update.model_dump(exclude_unset=True))
                return WebhookEntry(**webhook)
        raise __import__("fastapi").HTTPException(status_code=404, detail="Webhook not found")
    return mutate_json_list(_webhooks_file(identity.profile), patch)
