"""Workspace discovery and read-only directory listing endpoints."""

from __future__ import annotations

from pathlib import Path
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query

from ..dependencies import get_core_service
from ..errors import CoreApiError
from ..request_context import (
    RequestIdentity,
    profile_scope,
    require_identity,
    require_mutation_identity,
)
from ..schemas import WorkspaceEntriesResponse, WorkspacesResponse
from ..services import AresCoreService


router = APIRouter(prefix="/api", tags=["workspaces"])


@router.get("/workspaces", response_model=WorkspacesResponse)
def get_workspaces(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
):
    return service.workspaces(profile=identity.profile)


@router.get("/list", response_model=WorkspaceEntriesResponse)
def list_workspace(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[AresCoreService, Depends(get_core_service)],
    session_id: str = Query(min_length=1, max_length=256),
    path: str = Query(default=".", max_length=4096),
):
    return service.list_workspace(session_id, path, profile=identity.profile)


@router.get("/workspaces/suggest")
def suggest_workspaces(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    prefix: str = Query(default="", max_length=4096),
    limit: int = Query(default=12, ge=1, le=50),
):
    from api.workspace import list_workspace_suggestions

    with profile_scope(identity.profile):
        return {"suggestions": list_workspace_suggestions(prefix, limit)}


def _workspace_registry_mutation(identity: RequestIdentity, operation, payload: dict[str, Any]):
    try:
        with profile_scope(identity.profile):
            return operation(payload)
    except (ValueError, OSError, PermissionError) as exc:
        raise CoreApiError(400, str(exc)) from exc


def _add_workspace(payload: dict[str, Any]):
    from api.workspace import (
        _home_path,
        _is_blocked_system_path,
        _is_within,
        _strip_surrounding_quotes,
        load_workspaces,
        save_workspaces,
        validate_workspace_to_add,
    )

    raw_path = _strip_surrounding_quotes(str(payload.get("path") or "").strip())
    if not raw_path:
        raise ValueError("path is required")
    candidate = Path(raw_path).expanduser().resolve()
    home = _home_path()
    if _is_blocked_system_path(candidate) and not (
        home != Path("/") and (candidate == home or _is_within(candidate, home))
    ):
        raise ValueError(f"Path points to a system directory: {candidate}")
    if payload.get("create"):
        candidate.mkdir(parents=True, exist_ok=True)
    resolved = validate_workspace_to_add(raw_path)
    workspaces = load_workspaces()
    if any(item["path"] == str(resolved) for item in workspaces):
        raise ValueError("Workspace already in list")
    workspaces.append(
        {
            "path": str(resolved),
            "name": str(payload.get("name") or "").strip() or resolved.name,
        }
    )
    save_workspaces(workspaces)
    return {"ok": True, "workspaces": workspaces}


def _remove_workspace(payload: dict[str, Any]):
    from api.workspace import load_workspaces, save_workspaces

    path = str(payload.get("path") or "").strip()
    if not path:
        raise ValueError("path is required")
    workspaces = [item for item in load_workspaces() if item["path"] != path]
    save_workspaces(workspaces)
    return {"ok": True, "workspaces": workspaces}


def _rename_workspace(payload: dict[str, Any]):
    from api.workspace import load_workspaces, save_workspaces

    path = str(payload.get("path") or "").strip()
    name = str(payload.get("name") or "").strip()
    if not path or not name:
        raise ValueError("path and name are required")
    workspaces = load_workspaces()
    for item in workspaces:
        if item["path"] == path:
            item["name"] = name
            break
    else:
        raise CoreApiError(404, "Workspace not found")
    save_workspaces(workspaces)
    return {"ok": True, "workspaces": workspaces}


def _reorder_workspaces(payload: dict[str, Any]):
    from api.workspace import load_workspaces, save_workspaces

    paths = payload.get("paths")
    if not isinstance(paths, list) or not paths:
        raise ValueError("paths is required and must be a list")
    workspaces = load_workspaces()
    by_path = {item["path"]: item for item in workspaces}
    ordered = []
    seen = set()
    for raw in paths:
        path = str(raw).strip()
        if path in by_path and path not in seen:
            ordered.append(by_path[path])
            seen.add(path)
    ordered.extend(item for item in workspaces if item["path"] not in seen)
    save_workspaces(ordered)
    return {"ok": True, "workspaces": ordered}


@router.post("/workspaces/add")
def add_workspace(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    return _workspace_registry_mutation(identity, _add_workspace, payload)


@router.post("/workspaces/remove")
def remove_workspace(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    return _workspace_registry_mutation(identity, _remove_workspace, payload)


@router.post("/workspaces/rename")
def rename_workspace(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    return _workspace_registry_mutation(identity, _rename_workspace, payload)


@router.post("/workspaces/reorder")
def reorder_workspaces(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    return _workspace_registry_mutation(identity, _reorder_workspaces, payload)
