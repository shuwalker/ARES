"""FastAPI transport for the shared ARES Kanban data service."""

from __future__ import annotations

import asyncio
from types import SimpleNamespace
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Request

from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_identity, require_mutation_identity


router = APIRouter(prefix="/api/kanban", tags=["kanban"])


def _parsed(request: Request):
    return SimpleNamespace(path=request.url.path, query=request.url.query)


def _profile_call(profile: str | None, operation):
    try:
        with profile_scope(profile):
            return operation()
    except ImportError as exc:
        raise CoreApiError(503, f"kanban unavailable: {exc}") from exc
    except LookupError as exc:
        raise CoreApiError(404, str(exc)) from exc
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except RuntimeError as exc:
        raise CoreApiError(409, str(exc)) from exc


async def _call(identity: RequestIdentity, operation, *args, **kwargs):
    def invoke():
        return operation(*args, **kwargs)

    return await asyncio.to_thread(_profile_call, identity.profile, invoke)


async def _call_board(identity, request, payload, operation, *args, **kwargs):
    def invoke():
        return operation(*args, board=_board(request, payload), **kwargs)

    return await _call(identity, invoke)


def _board(request: Request, payload: dict[str, Any] | None = None):
    from api.kanban_bridge import _resolve_board, _resolve_board_from_body

    query_board = _resolve_board(_parsed(request))
    return query_board if query_board is not None else _resolve_board_from_body(payload or {})


@router.get("/boards")
async def boards(request: Request, identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.kanban_bridge import _list_boards_payload

    return await _call(identity, _list_boards_payload, _parsed(request))


@router.post("/boards")
async def create_board(payload: dict[str, Any], identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.kanban_bridge import _create_board_payload

    return await _call(identity, _create_board_payload, payload)


@router.patch("/boards/{slug}")
async def update_board(slug: str, payload: dict[str, Any], identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.kanban_bridge import _update_board_payload

    return await _call(identity, _update_board_payload, slug, payload)


@router.delete("/boards/{slug}")
async def delete_board(slug: str, request: Request, identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.kanban_bridge import _delete_board_payload

    return await _call(identity, _delete_board_payload, slug, _parsed(request))


@router.post("/boards/{slug}/switch")
async def switch_board(slug: str, identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.kanban_bridge import _switch_board_payload

    return await _call(identity, _switch_board_payload, slug)


@router.get("/board")
async def board(request: Request, identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.kanban_bridge import _board_payload

    return await _call(identity, _board_payload, _parsed(request))


@router.get("/config")
async def config(request: Request, identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.kanban_bridge import _config_payload

    return await _call_board(identity, request, None, _config_payload)


@router.patch("/config")
async def update_config(payload: dict[str, Any], identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.kanban_bridge import _update_config_payload

    return await _call(identity, _update_config_payload, payload)


@router.get("/stats")
async def stats(request: Request, identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.kanban_bridge import _stats_payload

    return await _call_board(identity, request, None, _stats_payload)


@router.get("/assignees")
async def assignees(request: Request, identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.kanban_bridge import _assignees_payload

    return await _call_board(identity, request, None, _assignees_payload)


@router.get("/events")
async def events(request: Request, identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.kanban_bridge import _events_payload

    return await _call(identity, _events_payload, _parsed(request))


@router.post("/dispatch")
async def dispatch(request: Request, identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.kanban_bridge import _dispatch_payload

    return await _call(identity, _dispatch_payload, _parsed(request))


@router.post("/tasks/bulk")
async def bulk_tasks(request: Request, payload: dict[str, Any], identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.kanban_bridge import _bulk_tasks_payload

    return await _call_board(identity, request, payload, _bulk_tasks_payload, payload)


@router.post("/tasks")
async def create_task(request: Request, payload: dict[str, Any], identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.kanban_bridge import _create_task_payload

    return await _call_board(identity, request, payload, _create_task_payload, payload)


@router.get("/tasks/{task_id}/log")
async def task_log(task_id: str, request: Request, identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.kanban_bridge import _task_log_payload

    result = await _call(identity, _task_log_payload, _parsed(request), task_id)
    if result is None:
        raise CoreApiError(404, "task not found")
    return result


@router.post("/tasks/{task_id}/comments")
async def comment(task_id: str, request: Request, payload: dict[str, Any], identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.kanban_bridge import _comment_payload

    return await _call_board(identity, request, payload, _comment_payload, task_id, payload)


@router.post("/tasks/{task_id}/{action}")
async def task_action(task_id: str, action: str, request: Request, payload: dict[str, Any], identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.kanban_bridge import _patch_task_payload, _task_action_payload

    if action == "patch":
        return await _call_board(identity, request, payload, _patch_task_payload, task_id, payload)
    if action not in {"block", "unblock"}:
        raise CoreApiError(404, "kanban endpoint not found")
    return await _call_board(
        identity,
        request,
        payload,
        _task_action_payload,
        task_id,
        payload,
        action,
    )


@router.patch("/tasks/{task_id}")
async def patch_task(task_id: str, request: Request, payload: dict[str, Any], identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.kanban_bridge import _patch_task_payload

    return await _call_board(identity, request, payload, _patch_task_payload, task_id, payload)


@router.get("/tasks/{task_id}")
async def task(task_id: str, request: Request, identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.kanban_bridge import _task_detail_payload

    result = await _call_board(identity, request, None, _task_detail_payload, task_id)
    if result is None:
        raise CoreApiError(404, "task not found")
    return result


@router.post("/links")
@router.post("/links/delete")
@router.delete("/links")
async def links(request: Request, payload: dict[str, Any], identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.kanban_bridge import _link_tasks_payload

    unlink = request.method == "DELETE" or request.url.path.endswith("/delete")
    return await _call_board(
        identity,
        request,
        payload,
        _link_tasks_payload,
        payload,
        unlink=unlink,
    )
