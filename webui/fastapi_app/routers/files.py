"""Workspace file mutation endpoints."""

from typing import Annotated

from fastapi import APIRouter, Depends

from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_mutation_identity
from ..schemas import FileCreate, FileDelete, FileMove, FileMutation, FileRename, FileSave


router = APIRouter(prefix="/api/file", tags=["files"])


def _run(operation, identity: RequestIdentity, *args, **kwargs):
    from api.file_operations import FileOperationError

    try:
        with profile_scope(identity.profile):
            return operation(*args, **kwargs)
    except FileOperationError as exc:
        raise CoreApiError(exc.status_code, str(exc)) from exc
    except (ValueError, FileNotFoundError, PermissionError, OSError) as exc:
        raise CoreApiError(400, str(exc)) from exc


@router.post("/delete")
def delete(payload: FileDelete, identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.file_operations import delete_file

    return _run(delete_file, identity, payload.session_id, payload.path, recursive=payload.recursive)


@router.post("/save")
def save(payload: FileSave, identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.file_operations import save_file

    return _run(save_file, identity, payload.session_id, payload.path, payload.content)


@router.post("/create")
def create(payload: FileCreate, identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.file_operations import create_file

    return _run(create_file, identity, payload.session_id, payload.path, payload.content)


@router.post("/create-dir")
def create_dir(payload: FileCreate, identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.file_operations import create_directory

    return _run(create_directory, identity, payload.session_id, payload.path)


@router.post("/rename")
def rename(payload: FileRename, identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.file_operations import rename_file

    return _run(rename_file, identity, payload.session_id, payload.path, payload.new_name)


@router.post("/move")
def move(payload: FileMove, identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.file_operations import move_file

    return _run(move_file, identity, payload.session_id, payload.path, payload.dest_dir)


@router.post("/path")
def path(payload: FileMutation, identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.file_operations import resolve_file_path

    return _run(resolve_file_path, identity, payload.session_id, payload.path)


@router.post("/office-save")
def office_save(payload: FileSave, identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.file_operations import save_office_file

    try:
        return _run(save_office_file, identity, payload.session_id, payload.path, payload.content)
    except ImportError as exc:
        raise CoreApiError(503, str(exc)) from exc


@router.post("/reveal")
def reveal(payload: FileMutation, identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.file_operations import reveal_file

    return _run(reveal_file, identity, payload.session_id, payload.path)


@router.post("/open-vscode")
def open_vscode(payload: FileMutation, identity: Annotated[RequestIdentity, Depends(require_mutation_identity)]):
    from api.file_operations import open_in_vscode

    return _run(open_in_vscode, identity, payload.session_id, payload.path)


__all__ = ["router"]
