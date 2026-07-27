"""Profile-scoped workspace project organization."""

from __future__ import annotations

import re
import time
from typing import Annotated, Any
import uuid

from fastapi import APIRouter, Depends

from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_identity, require_mutation_identity
from ..schemas import ProjectCreate, ProjectDelete, ProjectRename, ProjectUpdate


router = APIRouter(prefix="/api", tags=["projects"])
_COLOR = re.compile(r"^#[0-9a-fA-F]{3,8}$")


@router.get("/projects")
def projects(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    all_profiles: bool = False,
):
    from api.models import load_projects
    from api.profiles import _is_isolated_profile_mode, _profiles_match, get_active_profile_name

    with profile_scope(identity.profile):
        active = get_active_profile_name()
        rows = load_projects()
        scoped = rows if all_profiles else [row for row in rows if _profiles_match(row.get("profile"), active)]
        return {
            "projects": scoped,
            "all_profiles": all_profiles,
            "active_profile": active,
            "other_profile_count": 0 if all_profiles or _is_isolated_profile_mode() else len(rows) - len(scoped),
        }


def _validate_color(color: Any) -> str | None:
    if color is None or color == "":
        return color
    if not isinstance(color, str) or not _COLOR.fullmatch(color):
        raise CoreApiError(400, "Invalid color format")
    return color


@router.post("/projects/create")
def create_project(
    payload: ProjectCreate,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.models import load_projects, save_projects
    from api.profiles import _PROFILE_ID_RE, get_active_profile_name

    name = payload.name.strip()[:128]
    if not name:
        raise CoreApiError(400, "name required")
    requested_profile = str(payload.profile or "").strip()
    if requested_profile and requested_profile != "default" and not _PROFILE_ID_RE.fullmatch(requested_profile):
        raise CoreApiError(400, "invalid profile")
    with profile_scope(identity.profile):
        rows = load_projects()
        project = {
            "project_id": uuid.uuid4().hex[:12],
            "name": name,
            "color": _validate_color(payload.color),
            "profile": requested_profile or get_active_profile_name() or "default",
            "created_at": time.time(),
            "updated_at": time.time(),
            "description": payload.description.strip(),
            "domain": payload.domain.strip() or "General",
            "status": payload.status,
            "target_date": payload.target_date,
        }
        rows.append(project)
        save_projects(rows)
    return {"ok": True, "project": project}


@router.post("/projects/update")
def update_project(
    payload: ProjectUpdate,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.models import save_projects

    with profile_scope(identity.profile):
        rows, project = _owned_project(payload.project_id.strip())
        updates = payload.model_dump(exclude_unset=True, exclude={"project_id"})
        if "name" in updates:
            updates["name"] = str(updates["name"]).strip()
        if "description" in updates:
            updates["description"] = str(updates["description"]).strip()
        if "domain" in updates:
            updates["domain"] = str(updates["domain"]).strip() or "General"
        if "color" in updates:
            updates["color"] = _validate_color(updates["color"])
        project.update(updates)
        project["updated_at"] = time.time()
        save_projects(rows)
    return {"ok": True, "project": project}


def _owned_project(project_id: str):
    from api.models import load_projects
    from api.profiles import _profiles_match, get_active_profile_name

    rows = load_projects()
    project = next((row for row in rows if row.get("project_id") == project_id), None)
    if not project or not _profiles_match(project.get("profile"), get_active_profile_name()):
        raise CoreApiError(404, "Project not found")
    return rows, project


@router.post("/projects/rename")
def rename_project(
    payload: ProjectRename,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.models import save_projects

    project_id = payload.project_id.strip()
    name = payload.name.strip()[:128]
    if not project_id or not name:
        raise CoreApiError(400, "project_id and name are required")
    with profile_scope(identity.profile):
        rows, project = _owned_project(project_id)
        project["name"] = name
        if "color" in payload.model_fields_set:
            project["color"] = _validate_color(payload.color)
        save_projects(rows)
    return {"ok": True, "project": project}


@router.post("/projects/delete")
def delete_project(
    payload: ProjectDelete,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.models import all_sessions, get_session, save_projects

    project_id = payload.project_id.strip()
    if not project_id:
        raise CoreApiError(400, "project_id is required")
    with profile_scope(identity.profile):
        rows, _project = _owned_project(project_id)
        save_projects([row for row in rows if row.get("project_id") != project_id])
        for row in all_sessions():
            if row.get("project_id") != project_id:
                continue
            try:
                session = get_session(str(row.get("session_id") or ""))
                session.project_id = None
                session.save()
            except Exception:
                continue
    return {"ok": True}


__all__ = ["router"]
