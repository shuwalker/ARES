"""Workspace-scoped Git operations."""

from __future__ import annotations

from pathlib import Path
from typing import Annotated, Any, Callable

from fastapi import APIRouter, Depends, Query

from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_identity, require_mutation_identity


router = APIRouter(prefix="/api/git", tags=["git"])
legacy_router = APIRouter(tags=["git"])


def _git_error(exc: Exception, status_code: int = 400) -> CoreApiError:
    return CoreApiError(
        status_code,
        str(exc),
        code=str(getattr(exc, "code", "git_failed") or "git_failed"),
    )


def _session(session_id: str):
    from api.models import get_session

    if not session_id:
        raise CoreApiError(400, "session_id required")
    try:
        return get_session(session_id)
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc


def _workspace(session_id: str) -> tuple[Any, Path]:
    session = _session(session_id)
    return session, Path(session.workspace)


def _paths(payload: dict[str, Any]) -> list[str]:
    raw = payload.get("paths")
    if raw is None and payload.get("path"):
        raw = [payload.get("path")]
    if isinstance(raw, str):
        raw = [raw]
    if not isinstance(raw, list):
        raise CoreApiError(400, "paths must be a list")
    return [str(item) for item in raw]


def _require_destructive(session) -> None:
    from api.config import STREAMS, STREAMS_LOCK
    from api.workspace_git import WORKSPACE_GIT_DESTRUCTIVE_ENV, workspace_git_destructive_enabled

    if not workspace_git_destructive_enabled():
        raise CoreApiError(
            403,
            f"Destructive workspace Git operations are disabled. Set {WORKSPACE_GIT_DESTRUCTIVE_ENV}=1 to enable them.",
            code="destructive_git_disabled",
        )
    stream_id = getattr(session, "active_stream_id", None)
    if stream_id:
        with STREAMS_LOCK:
            active = stream_id in STREAMS
        if active:
            raise CoreApiError(
                409,
                "A session run is active. Wait for it to finish before running this Git operation.",
                code="active_stream",
            )


@router.get("/status")
def status(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
):
    from api.workspace_git import GitWorkspaceError, git_status

    try:
        with profile_scope(identity.profile):
            _, workspace = _workspace(session_id)
            return {"git": git_status(workspace)}
    except GitWorkspaceError as exc:
        raise _git_error(exc) from exc


@router.get("/branches")
def branches(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
):
    from api.workspace_git import GitWorkspaceError, git_branches

    try:
        with profile_scope(identity.profile):
            _, workspace = _workspace(session_id)
            return {"branches": git_branches(workspace)}
    except GitWorkspaceError as exc:
        raise _git_error(exc) from exc


@router.get("/diff")
def diff(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
    path: str = Query(min_length=1, max_length=4096),
    kind: str = Query(default="unstaged", max_length=32),
):
    from api.workspace_git import GitWorkspaceError, git_diff

    try:
        with profile_scope(identity.profile):
            _, workspace = _workspace(session_id)
            return {"diff": git_diff(workspace, path, kind)}
    except GitWorkspaceError as exc:
        raise _git_error(exc) from exc


@legacy_router.get("/api/git-info")
def legacy_git_info(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(min_length=1, max_length=256),
):
    from api.workspace_git import GitWorkspaceError, git_status

    try:
        with profile_scope(identity.profile):
            _, workspace = _workspace(session_id)
            result = git_status(workspace)
    except GitWorkspaceError as exc:
        raise _git_error(exc) from exc
    totals = result.get("totals") or {}
    info = None
    if result.get("is_git"):
        info = {
            "branch": result.get("branch"),
            "dirty": totals.get("changed", 0),
            "modified": (totals.get("staged", 0) or 0) + (totals.get("unstaged", 0) or 0),
            "untracked": totals.get("untracked", 0),
            "ahead": result.get("ahead", 0),
            "behind": result.get("behind", 0),
            "is_git": True,
        }
    return {"git": info}


def _mutate(
    payload: dict[str, Any],
    profile: str | None,
    operation: Callable[[Path], dict[str, Any]],
    *,
    destructive: bool = True,
):
    from api.workspace_git import GitWorkspaceError

    try:
        with profile_scope(profile):
            session, workspace = _workspace(str(payload.get("session_id") or ""))
            if destructive:
                _require_destructive(session)
            return operation(workspace)
    except GitWorkspaceError as exc:
        raise _git_error(exc) from exc


@router.post("/stage")
def stage(payload: dict[str, Any], identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.workspace_git import git_stage

    paths = _paths(payload)
    result = _mutate(payload, identity.profile, lambda workspace: git_stage(workspace, paths))
    return {"ok": True, "git": result}


@router.post("/unstage")
def unstage(payload: dict[str, Any], identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.workspace_git import git_unstage

    paths = _paths(payload)
    result = _mutate(payload, identity.profile, lambda workspace: git_unstage(workspace, paths))
    return {"ok": True, "git": result}


@router.post("/discard")
def discard(payload: dict[str, Any], identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.workspace_git import git_discard

    paths = _paths(payload)
    result = _mutate(
        payload,
        identity.profile,
        lambda workspace: git_discard(
            workspace,
            paths,
            delete_untracked=bool(payload.get("delete_untracked")),
        ),
    )
    return {"ok": True, "git": result}


def _fallback_commit_message(prompt: dict[str, Any], paths: list[str] | None = None) -> str:
    selected = [Path(path).name for path in (paths or []) if str(path).strip()]
    if selected:
        if len(selected) == 1:
            return f"Update {selected[0]}"
        return f"Update {selected[0]} and {len(selected) - 1} related files"
    user_prompt = str(prompt.get("user_prompt") or "")
    for line in user_prompt.splitlines():
        stripped = line.strip()
        if stripped.startswith("diff --git "):
            candidate = stripped.rsplit(" b/", 1)[-1]
            if candidate:
                return f"Update {Path(candidate).name}"
    return "Apply staged workspace changes"


@router.post("/commit-message")
def commit_message(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.workspace_git import GitWorkspaceError, staged_commit_message_prompt

    try:
        with profile_scope(identity.profile):
            _, workspace = _workspace(str(payload.get("session_id") or ""))
            prompt = staged_commit_message_prompt(workspace)
    except GitWorkspaceError as exc:
        raise _git_error(exc) from exc
    return {
        "ok": True,
        "message": _fallback_commit_message(prompt),
        "truncated": bool(prompt.get("truncated")),
        "generated_by": "deterministic_fallback",
    }


@router.post("/commit-message-selected")
def selected_commit_message(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.workspace_git import GitWorkspaceError, selected_commit_message_prompt

    paths = _paths(payload)
    try:
        with profile_scope(identity.profile):
            _, workspace = _workspace(str(payload.get("session_id") or ""))
            prompt = selected_commit_message_prompt(workspace, paths)
    except GitWorkspaceError as exc:
        raise _git_error(exc) from exc
    return {
        "ok": True,
        "message": _fallback_commit_message(prompt, paths),
        "truncated": bool(prompt.get("truncated")),
        "generated_by": "deterministic_fallback",
    }


@router.post("/commit")
def commit(payload: dict[str, Any], identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.workspace_git import git_commit

    if "message" not in payload:
        raise CoreApiError(400, "Missing required field: message")
    return _mutate(
        payload,
        identity.profile,
        lambda workspace: git_commit(workspace, str(payload.get("message") or "")),
    )


@router.post("/commit-selected")
def commit_selected(payload: dict[str, Any], identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.workspace_git import git_commit_selected

    if "message" not in payload:
        raise CoreApiError(400, "Missing required field: message")
    paths = _paths(payload)
    return _mutate(
        payload,
        identity.profile,
        lambda workspace: git_commit_selected(workspace, str(payload.get("message") or ""), paths),
    )


def _remote(payload: dict[str, Any], identity: RequestIdentity, action: str):
    from api.workspace_git import git_fetch, git_pull, git_push

    operations = {"fetch": git_fetch, "pull": git_pull, "push": git_push}
    return _mutate(
        payload,
        identity.profile,
        operations[action],
        destructive=action != "fetch",
    )


@router.post("/fetch")
def fetch(payload: dict[str, Any], identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    return _remote(payload, identity, "fetch")


@router.post("/pull")
def pull(payload: dict[str, Any], identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    return _remote(payload, identity, "pull")


@router.post("/push")
def push(payload: dict[str, Any], identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    return _remote(payload, identity, "push")


def _checkout_payload(result: dict[str, Any]) -> dict[str, Any]:
    return {
        "ok": True,
        "git": result.get("status"),
        "branches": result.get("branches"),
        "current_branch": result.get("current_branch"),
        "message": result.get("message", ""),
    }


@router.post("/checkout")
def checkout(payload: dict[str, Any], identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.workspace_git import git_checkout

    for field in ("ref", "mode"):
        if field not in payload:
            raise CoreApiError(400, f"Missing required field: {field}")
    result = _mutate(
        payload,
        identity.profile,
        lambda workspace: git_checkout(
            workspace,
            str(payload.get("ref") or ""),
            str(payload.get("mode") or "local"),
            new_branch=payload.get("new_branch"),
            track=bool(payload.get("track")),
            dirty_mode=str(payload.get("dirty_mode") or "block"),
        ),
    )
    return _checkout_payload(result)


@router.post("/stash-checkout")
def stash_checkout(payload: dict[str, Any], identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.workspace_git import git_stash_and_checkout

    for field in ("ref", "mode"):
        if field not in payload:
            raise CoreApiError(400, f"Missing required field: {field}")
    result = _mutate(
        payload,
        identity.profile,
        lambda workspace: git_stash_and_checkout(
            workspace,
            str(payload.get("ref") or ""),
            str(payload.get("mode") or "local"),
            new_branch=payload.get("new_branch"),
            track=bool(payload.get("track")),
        ),
    )
    return _checkout_payload(result) | {
        "stash_name": result.get("stash_name", ""),
        "stashed": bool(result.get("stashed")),
        "restored_stash": result.get("restored_stash"),
        "restore_failed": bool(result.get("restore_failed")),
        "restore_error": result.get("restore_error", ""),
        "restore_stash": result.get("restore_stash"),
    }


__all__ = ["legacy_router", "router"]
