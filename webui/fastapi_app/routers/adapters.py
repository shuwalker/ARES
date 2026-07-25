"""Framework-neutral connection, model, and tool discovery endpoints."""

from typing import Annotated

from fastapi import APIRouter, Depends

from ..adapters import AdapterError, AdapterRegistry
from ..dependencies import get_adapter_registry
from ..errors import CoreApiError
from ..request_context import RequestIdentity, require_identity
from ..schemas import (
    ConnectionModelsResponse,
    ConnectionsResponse,
    ConnectionTestResponse,
    McpToolsResponse,
)


router = APIRouter(tags=["connections"])


def _translate_adapter_error(exc: AdapterError) -> CoreApiError:
    return CoreApiError(
        exc.status_code,
        exc.message,
        code=exc.code,
        context=exc.context,
    )


@router.get("/api/connections", response_model=ConnectionsResponse)
def connections(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    registry: Annotated[AdapterRegistry, Depends(get_adapter_registry)],
):
    try:
        return registry.connection_records(profile=identity.profile)
    except AdapterError as exc:
        raise _translate_adapter_error(exc) from exc


@router.get(
    "/api/connections/{connection_id}/models",
    response_model=ConnectionModelsResponse,
)
def connection_models(
    connection_id: str,
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    registry: Annotated[AdapterRegistry, Depends(get_adapter_registry)],
):
    try:
        return registry.models(connection_id, profile=identity.profile)
    except AdapterError as exc:
        raise _translate_adapter_error(exc) from exc


@router.get(
    "/api/connections/{connection_id}/test",
    response_model=ConnectionTestResponse,
)
def test_connection(
    connection_id: str,
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    registry: Annotated[AdapterRegistry, Depends(get_adapter_registry)],
):
    try:
        return registry.test_connection(connection_id, profile=identity.profile)
    except AdapterError as exc:
        raise _translate_adapter_error(exc) from exc


@router.get("/api/mcp/tools", response_model=McpToolsResponse)
def mcp_tools(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    registry: Annotated[AdapterRegistry, Depends(get_adapter_registry)],
):
    try:
        return registry.tool_adapter("mcp").list_tools(profile=identity.profile)
    except AdapterError as exc:
        raise _translate_adapter_error(exc) from exc
