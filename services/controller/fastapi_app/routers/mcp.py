"""MCP server configuration endpoints."""

from typing import Annotated

from fastapi import APIRouter, Depends

from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_identity, require_mutation_identity
from ..schemas import McpServerToggle, McpServerUpdate


router = APIRouter(prefix="/api/mcp/servers", tags=["mcp"])


def _call(operation, identity: RequestIdentity, *args):
    from api.mcp_config import McpConfigError

    try:
        with profile_scope(identity.profile):
            return operation(*args)
    except McpConfigError as exc:
        raise CoreApiError(exc.status_code, str(exc)) from exc


@router.get("")
def servers(identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.mcp_config import list_servers

    return _call(list_servers, identity)


@router.put("/{name}")
def update(
    name: str,
    payload: McpServerUpdate,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.mcp_config import update_server

    return _call(update_server, identity, name, payload.model_dump(exclude_none=True))


@router.patch("/{name}")
def toggle(
    name: str,
    payload: McpServerToggle,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.mcp_config import toggle_server

    return _call(toggle_server, identity, name, payload.enabled)


@router.delete("/{name}")
def delete(name: str, identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.mcp_config import delete_server

    return _call(delete_server, identity, name)


__all__ = ["router"]
