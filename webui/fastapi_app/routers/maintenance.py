"""System status, dashboard, extensions, updates, commands, and rollback."""

from __future__ import annotations

import importlib
import logging
import os
import signal
import threading
import time
from pathlib import Path
from typing import Annotated, Any, Literal

from fastapi import APIRouter, Depends, Query, Request, Response

from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_identity, require_mutation_identity


router = APIRouter(tags=["maintenance"])
logger = logging.getLogger(__name__)


@router.get("/api/system/health")
def system_health(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.system_health import build_system_health_payload

    return build_system_health_payload()


@router.get("/api/dashboard/status")
def dashboard_status(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.dashboard_probe import get_dashboard_status

    return get_dashboard_status()


@router.get("/api/dashboard/config")
def dashboard_config(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.dashboard_probe import get_dashboard_config

    try:
        return get_dashboard_config()
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc


@router.post("/api/dashboard/config")
def save_dashboard(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.dashboard_probe import save_dashboard_config

    try:
        return save_dashboard_config(payload)
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc


@router.get("/api/extensions/status")
def extension_status(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.extensions import get_extension_status

    return get_extension_status()


@router.get("/api/extensions/registry")
def extension_registry(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.extensions import get_extension_registry

    return get_extension_registry()


def _extension_error(exc: Exception) -> CoreApiError:
    return CoreApiError(int(getattr(exc, "status", 400)), str(exc))


@router.post("/api/extensions/toggle")
def extension_toggle(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.extensions import ExtensionToggleError, set_extension_user_enabled

    try:
        return set_extension_user_enabled(payload.get("id"), payload.get("enabled"))
    except ExtensionToggleError as exc:
        raise _extension_error(exc) from exc


@router.post("/api/extensions/sidecar-proxy-consent")
def extension_proxy_consent(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.extensions import ExtensionSidecarProxyError, set_extension_sidecar_proxy_consent

    try:
        return set_extension_sidecar_proxy_consent(payload.get("id"), payload.get("approved"))
    except ExtensionSidecarProxyError as exc:
        raise _extension_error(exc) from exc


@router.get("/api/extensions/{extension_id}/sidecar/{proxy_path:path}")
@router.head("/api/extensions/{extension_id}/sidecar/{proxy_path:path}")
@router.get("/api/extensions/{extension_id}/sidecar")
@router.head("/api/extensions/{extension_id}/sidecar")
async def extension_sidecar_read(
    extension_id: str,
    request: Request,
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    proxy_path: str = "",
):
    from api.extension_proxy import proxy_extension_sidecar

    return await proxy_extension_sidecar(request, extension_id, proxy_path)


@router.api_route(
    "/api/extensions/{extension_id}/sidecar/{proxy_path:path}",
    methods=["POST", "PUT", "PATCH", "DELETE"],
)
@router.api_route(
    "/api/extensions/{extension_id}/sidecar",
    methods=["POST", "PUT", "PATCH", "DELETE"],
)
async def extension_sidecar_mutation(
    extension_id: str,
    request: Request,
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    proxy_path: str = "",
):
    from api.extension_proxy import proxy_extension_sidecar

    return await proxy_extension_sidecar(request, extension_id, proxy_path)


@router.post("/api/extensions/install")
def extension_install(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.extensions import ExtensionInstallError, install_extension

    try:
        return install_extension(payload.get("id"), payload.get("download_url"), payload.get("sha256"))
    except ExtensionInstallError as exc:
        raise _extension_error(exc) from exc


@router.post("/api/extensions/uninstall")
def extension_uninstall(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.extensions import ExtensionInstallError, uninstall_extension

    try:
        return uninstall_extension(payload.get("id"))
    except ExtensionInstallError as exc:
        raise _extension_error(exc) from exc


@router.get("/api/plugins")
def plugins(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.plugins import get_plugin_metadata

    return {"plugins": get_plugin_metadata()}


@router.get("/api/commands")
def commands(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.commands import list_commands

    return {"commands": list_commands()}


@router.get("/api/commands/bundles")
def command_bundles(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.commands import list_command_bundles

    return {"bundles": list_command_bundles()}


@router.post("/api/commands/bundles/resolve")
def resolve_command_bundle(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.commands import resolve_bundle_command

    command = str(payload.get("command") or "").strip()
    if not command:
        raise CoreApiError(400, "command is required")
    try:
        return resolve_bundle_command(command)
    except KeyError as exc:
        raise CoreApiError(404, "Bundle command not found") from exc
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except RuntimeError as exc:
        raise CoreApiError(500, str(exc)) from exc


@router.post("/api/commands/exec")
def execute_command(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.commands import execute_agent_command, execute_plugin_command

    command = str(payload.get("command") or "").strip()
    if not command:
        raise CoreApiError(400, "command is required")
    try:
        return {"output": execute_agent_command(command)}
    except KeyError:
        pass
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except RuntimeError as exc:
        raise CoreApiError(500, str(exc)) from exc
    try:
        return {"output": execute_plugin_command(command)}
    except KeyError as exc:
        raise CoreApiError(404, "Plugin command not found") from exc
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except RuntimeError as exc:
        raise CoreApiError(500, str(exc)) from exc


@router.get("/api/commands/moa/resolve")
def moa_configuration(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.commands import resolve_moa_config

    try:
        return resolve_moa_config()
    except RuntimeError as exc:
        raise CoreApiError(503, str(exc)) from exc


def _update_preferences() -> tuple[dict[str, Any], bool]:
    from api.config import load_settings

    settings = load_settings()
    return settings, not bool(settings.get("ignore_agent_updates"))


@router.get("/api/updates/check")
def cached_updates(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    from api.updates import cached_update_status

    with profile_scope(identity.profile):
        settings, include_agent = _update_preferences()
        if not settings.get("check_for_updates", True):
            return {"disabled": True}
        return cached_update_status(include_agent=include_agent)


@router.post("/api/updates/check")
def check_updates(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.updates import check_for_updates

    with profile_scope(identity.profile):
        settings, include_agent = _update_preferences()
        if not settings.get("check_for_updates", True):
            return {"disabled": True}
        channel = payload.get("channel")
        if channel not in {"stable", "experimental"}:
            channel = settings.get("update_channel")
        return check_for_updates(
            force=bool(payload.get("force", False)),
            include_agent=include_agent,
            channel=channel,
        )


def _update_target(payload: dict[str, Any]) -> Literal["webui", "agent"]:
    target = str(payload.get("target") or "")
    if target not in {"webui", "agent"}:
        raise CoreApiError(400, 'target must be "webui" or "agent"')
    return target  # type: ignore[return-value]


def _update_channel(payload: dict[str, Any]) -> str | None:
    channel = payload.get("channel")
    return str(channel) if channel in {"stable", "experimental"} else None


@router.post("/api/updates/apply")
def apply_update(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.updates import apply_update as apply

    return apply(_update_target(payload), _update_channel(payload))


@router.post("/api/updates/force")
def force_update(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.updates import apply_force_update

    return apply_force_update(_update_target(payload), _update_channel(payload))


@router.post("/api/updates/clear_lock")
def clear_update_lock(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.updates import apply_clear_lock

    return apply_clear_lock(_update_target(payload))


@router.post("/api/updates/summary")
def update_summary(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.updates import summarize_update_payload

    updates = payload.get("updates")
    return summarize_update_payload(
        updates if isinstance(updates, dict) else {},
        target=payload.get("target"),
    )


@router.get("/api/logs")
def logs(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    file: str = "agent",
    tail: str = "200",
):
    from api.config import STATE_DIR

    filenames = {"agent": "agent.log", "errors": "errors.log", "gateway": "gateway.log"}
    if file not in filenames:
        raise CoreApiError(400, "Unknown log file")
    try:
        selected_tail = int(tail)
    except (TypeError, ValueError):
        selected_tail = 200
    if selected_tail not in {100, 200, 500, 1000}:
        selected_tail = 200
    with profile_scope(identity.profile):
        path = Path(STATE_DIR) / "logs" / filenames[file]
    if not path.exists():
        return {
            "file": file, "tail": selected_tail, "lines": [], "text": "",
            "truncated": False, "total_bytes": 0, "mtime": None,
            "hint": f"{filenames[file]} was not found",
        }
    try:
        stat = path.stat()
        total_bytes = stat.st_size
        data = path.read_bytes()[-4 * 1024 * 1024 :]
    except OSError as exc:
        raise CoreApiError(400, f"Could not read log: {exc}") from exc
    lines = data.decode("utf-8", errors="replace").splitlines()[-selected_tail:]
    return {
        "file": file, "tail": selected_tail, "lines": lines, "text": "\n".join(lines),
        "truncated": total_bytes > len(data), "total_bytes": total_bytes,
        "mtime": stat.st_mtime, "hint": "",
    }


@router.post("/api/admin/reload")
def reload_models_module(
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api import models

    importlib.reload(models)
    return {"status": "ok", "reloaded": "api.models"}


@router.post("/api/process-complete-ack")
def deprecated_process_complete_ack(response: Response):
    response.status_code = 410
    response.headers["X-Replaced-By"] = "/api/bg-task-complete-ack"
    return {
        "error": "gone: /api/process-complete-ack was replaced by /api/bg-task-complete-ack",
        "replaced_by": "/api/bg-task-complete-ack",
    }


@router.post("/api/csp-report", status_code=204)
async def csp_report(request: Request):
    from api.client_reports import _CSP_MAX_BYTES, record_csp_report

    raw = await _bounded_request_body(request, _CSP_MAX_BYTES)
    record_csp_report(request.client.host if request.client else "unknown", raw)
    return Response(status_code=204)


@router.post("/api/client-events/log", status_code=204)
async def client_event_log(
    request: Request,
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.client_reports import _CLIENT_MAX_BYTES, record_client_event

    raw = await _bounded_request_body(request, _CLIENT_MAX_BYTES)
    record_client_event(request.client.host if request.client else "unknown", raw)
    return Response(status_code=204)


async def _bounded_request_body(request: Request, maximum: int) -> bytes:
    """Read at most ``maximum`` bytes without buffering an untrusted body."""
    chunks = bytearray()
    async for chunk in request.stream():
        remaining = maximum - len(chunks)
        if remaining <= 0:
            break
        chunks.extend(chunk[:remaining])
    return bytes(chunks)


def _schedule_shutdown() -> None:
    def stop() -> None:
        time.sleep(0.3)
        os.kill(os.getpid(), signal.SIGINT)

    threading.Thread(target=stop, daemon=True).start()


@router.post("/api/shutdown")
def shutdown(
    request: Request,
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.shutdown_audit import safe_log_value

    logger.info(
        "[shutdown-request] remote=%s method=%s path=%s ua=%s",
        safe_log_value(request.client.host if request.client else None),
        safe_log_value(request.method),
        safe_log_value(request.url.path),
        safe_log_value(request.headers.get("user-agent")),
    )
    _schedule_shutdown()
    return {"status": "shutting_down"}


@router.get("/api/rollback/list")
def rollback_list(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    workspace: str = Query(min_length=1, max_length=4096),
):
    from api.rollback import list_checkpoints

    try:
        return list_checkpoints(workspace)
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc


@router.get("/api/rollback/diff")
def rollback_diff(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    workspace: str = Query(min_length=1, max_length=4096),
    checkpoint: str = Query(min_length=1, max_length=256),
):
    from api.rollback import get_checkpoint_diff

    try:
        return get_checkpoint_diff(workspace, checkpoint)
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc


@router.post("/api/rollback/restore")
def rollback_restore(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.rollback import restore_checkpoint

    workspace = str(payload.get("workspace") or "")
    checkpoint = str(payload.get("checkpoint") or "")
    if not workspace or not checkpoint:
        raise CoreApiError(400, "workspace and checkpoint are required")
    try:
        return restore_checkpoint(workspace, checkpoint)
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc


__all__ = ["router"]
