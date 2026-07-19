"""ARES identity, companion presentation, backend, and device contracts."""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import APIRouter, Depends, Query

from ..adapters import AdapterError, AdapterRegistry
from ..dependencies import get_adapter_registry
from ..errors import CoreApiError
from ..request_context import RequestIdentity, profile_scope, require_identity, require_mutation_identity
from .onboarding import require_onboarding_mutation


router = APIRouter(tags=["ares"])


@router.get("/api/personalities")
def personalities(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.config import get_config, reload_config

    reload_config()
    raw = (get_config().get("agent") or {}).get("personalities") or {}
    items = []
    if isinstance(raw, dict):
        for name, value in raw.items():
            description = ""
            if isinstance(value, dict):
                description = str(value.get("description") or "")
            elif isinstance(value, str):
                description = value[:80] + ("..." if len(value) > 80 else "")
            items.append({"name": name, "description": description})
    return {"personalities": items}


@router.post("/api/personality/set")
def set_session_personality(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.config import _get_session_agent_lock, get_config, reload_config
    from api.models import get_session

    session_id = str(payload.get("session_id") or "").strip()
    if not session_id:
        raise CoreApiError(400, "session_id is required")
    if "name" not in payload:
        raise CoreApiError(400, "Missing required field: name")
    name = str(payload.get("name") or "").strip()
    with profile_scope(identity.profile):
        try:
            session = get_session(session_id)
        except KeyError as exc:
            raise CoreApiError(404, "Session not found") from exc
        if getattr(session, "read_only", False) or getattr(session, "is_subagent", False):
            raise CoreApiError(400, "Subagent sessions are view-only and cannot be modified from WebUI")
        prompt = ""
        if name:
            reload_config()
            personalities = (get_config().get("agent") or {}).get("personalities") or {}
            if not isinstance(personalities, dict) or name not in personalities:
                raise CoreApiError(404, f'Personality "{name}" not found in config.yaml')
            value = personalities[name]
            if isinstance(value, dict):
                parts = [value.get("system_prompt") or value.get("prompt") or ""]
                if value.get("tone"):
                    parts.append(f"Tone: {value['tone']}")
                if value.get("style"):
                    parts.append(f"Style: {value['style']}")
                prompt = "\n".join(part for part in parts if part)
            else:
                prompt = str(value)
        with _get_session_agent_lock(session_id):
            session.personality = name or None
            session.save()
    return {"ok": True, "personality": session.personality, "prompt": prompt}


@router.get("/api/ares/personas")
def personas(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.persona import list_personas

    try:
        return {"personas": list_personas()}
    except Exception as exc:
        raise CoreApiError(400, f"Failed to list personas: {exc}") from exc


@router.get("/api/ares/characters")
def characters(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.characters import list_characters

    try:
        return {"characters": list_characters()}
    except Exception as exc:
        raise CoreApiError(400, f"Failed to list characters: {exc}") from exc


@router.get("/api/ares/character")
def character(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
    id: str = Query(min_length=1, max_length=256),
):
    from api.characters import get_character

    try:
        result = get_character(id)
    except Exception as exc:
        raise CoreApiError(400, f"Failed to load character: {exc}") from exc
    if result is None:
        raise CoreApiError(404, "Character not found")
    return {"character": result}


@router.get("/api/ares/persona/current")
def current_persona(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.config import get_config

    return {"persona_id": str(get_config().get("ares_persona") or "").strip()}


def _save_config_values(values: dict[str, Any]) -> None:
    from api.config import (
        _get_config_path,
        _load_yaml_config_file,
        _save_yaml_config_file,
        reload_config,
    )

    path = _get_config_path()
    config = _load_yaml_config_file(path)
    config.update(values)
    _save_yaml_config_file(path, config)
    reload_config()


@router.get("/api/ares/persona/set")
@router.post("/api/ares/persona/set")
def set_persona(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    persona_id = str(payload.get("persona_id") or "").strip()
    try:
        with profile_scope(identity.profile):
            _save_config_values({"ares_persona": persona_id})
    except Exception as exc:
        raise CoreApiError(400, f"Failed to save persona: {exc}") from exc
    return {"ok": True, "persona_id": persona_id}


def _session(session_id: str):
    from api.models import get_session

    try:
        return get_session(session_id)
    except KeyError as exc:
        raise CoreApiError(404, "Session not found") from exc


@router.get("/api/ares/backend")
def backend(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(default="", max_length=256),
):
    from api.ares_capabilities import capabilities_for_backend
    from api.backend_selector import backend_status, get_active_backend, get_session_backend
    from api.config import get_config

    with profile_scope(identity.profile):
        config = get_config()
        default_backend = get_active_backend(config)
        current = default_backend
        scope = "default"
        if session_id:
            current = get_session_backend(_session(session_id), config)
            scope = "session"
        return {
            "current": current,
            "default": default_backend,
            "scope": scope,
            "session_id": session_id or None,
            "status": backend_status(),
            "capabilities": capabilities_for_backend(current),
        }


@router.get("/api/ares/backend/set")
@router.post("/api/ares/backend/set")
def set_backend(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    registry: Annotated[AdapterRegistry, Depends(get_adapter_registry)],
):
    from api.ares_capabilities import capabilities_for_backend

    requested = str(payload.get("backend") or "").strip().lower()
    if not requested:
        raise CoreApiError(400, "A runtime connection is required.")
    try:
        backend_name = registry.execution_adapter(requested).adapter_id
    except AdapterError as exc:
        raise CoreApiError(
            exc.status_code,
            exc.message,
            code=exc.code,
            context=exc.context,
        ) from exc
    session_id = str(payload.get("session_id") or "").strip()
    with profile_scope(identity.profile):
        if session_id:
            session = _session(session_id)
            session.ares_backend = backend_name
            session.save(touch_updated_at=False)
            return {
                "ok": True,
                "backend": backend_name,
                "scope": "session",
                "session_id": session_id,
                "capabilities": capabilities_for_backend(backend_name),
            }
        _save_config_values({"ares_backend": backend_name})
    return {
        "ok": True,
        "backend": backend_name,
        "scope": "default",
        "capabilities": capabilities_for_backend(backend_name),
    }


@router.get("/api/ares/self-persistence")
def self_persistence(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.ares_self_persistence import build_self_persistence_contract
    from api.config import get_config

    return {"self_persistence": build_self_persistence_contract(get_config())}


@router.get("/api/ares/runtime-context")
def runtime_context(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.ares_runtime_context import build_runtime_context
    from api.backend_selector import get_active_backend
    from api.config import get_config

    config = get_config()
    return {"runtime_context": build_runtime_context(backend=get_active_backend(config))}


@router.get("/api/ares/tools")
def tools(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.ares_tool_adapter import register_ares_tools

    # This is a JSON discovery contract, not an executable in-process JROS
    # registry. MCP-shaped schemas contain no Python classes or callables and
    # are therefore safe to serialize regardless of the active runtime.
    return {"tools": register_ares_tools(target="mcp")}


@router.get("/api/ares/identity")
def identity(
    request_identity: Annotated[RequestIdentity, Depends(require_identity)],
    session_id: str = Query(default="", max_length=256),
):
    from api.ares_identity import build_identity_payload
    from api.backend_selector import get_active_backend, get_session_backend
    from api.config import get_config, load_settings
    from api.profiles import get_active_profile_name

    with profile_scope(request_identity.profile):
        config = get_config()
        backend_name = get_active_backend(config)
        if session_id:
            backend_name = get_session_backend(_session(session_id), config)
        persona_id = str(config.get("ares_persona") or "").strip() or None
        bot_name = str((load_settings() or {}).get("bot_name") or "").strip() or None
        return build_identity_payload(
            profile=get_active_profile_name(),
            bot_name=bot_name,
            backend=backend_name,
            persona_id=persona_id,
        )


@router.get("/api/ares/device/status")
def device_status(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.ares_devices import device_status as status
    from api.config import get_config

    return status(get_config())


@router.get("/api/ares/devices")
def devices(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    from api.ares_devices import device_status as status, load_registry
    from api.config import get_config

    config = get_config()
    return {"current": status(config), "registry": load_registry(config)}


@router.get("/api/ares/adapters")
def legacy_adapters(_identity: Annotated[RequestIdentity, Depends(require_identity)]):
    """Legacy adapter inventory retained beside the neutral connections API."""
    from api.backends.router import get_router

    try:
        backends = get_router().backends
        return {
            name: {
                "available": backend.is_available(),
                "label": backend.get_backend_name(),
                "health": backend.health(),
                "identity_projection": backend.identity_projection(),
                "capabilities": backend.capabilities(),
                "chat_session_support": backend.chat_session_support(),
                "tools": backend.tools(),
                "settings_schema": backend.settings_schema(),
            }
            for name, backend in backends.items()
        }
    except Exception as exc:
        raise CoreApiError(400, f"Failed to list ARES adapters: {exc}") from exc


@router.get("/api/ares/approvals/pending")
def all_pending_approvals(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    from api.route_approvals import _lock, _pending

    approvals = []
    with _lock:
        for session_id, entries in _pending.items():
            for entry in entries if isinstance(entries, list) else []:
                approvals.append(
                    {
                        "session_id": session_id,
                        "approval_id": entry.get("approval_id"),
                        "command": entry.get("command") or entry.get("message") or "",
                        "type": entry.get("type") or "tool",
                        "created_at": entry.get("created_at") or "",
                        "tool_name": entry.get("tool_name") or entry.get("name") or "",
                    }
                )
    return {"approvals": approvals}


@router.get("/api/ares/audit/logs")
def audit_logs(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    import json

    from api.paths import HOME

    records = []
    audit_file = HOME / ".ares" / "audit.log"
    try:
        if audit_file.is_file():
            with audit_file.open("r", encoding="utf-8") as source:
                for line in source:
                    try:
                        record = json.loads(line)
                    except (TypeError, ValueError):
                        continue
                    if isinstance(record, dict):
                        records.append(record)
    except OSError as exc:
        raise CoreApiError(400, f"Failed to fetch audit logs: {exc}") from exc
    return {"logs": records[-100:]}


@router.post("/api/ares/device/configure")
def configure_device(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_onboarding_mutation)],
):
    from api.ares_devices import device_status as status, normalize_config_update, register_device
    from api.config import get_config

    with profile_scope(identity.profile):
        updates = normalize_config_update(payload, get_config())
        _save_config_values(updates)
        config = get_config()
        registration = register_device(config=config)
    return {"ok": True, "updates": updates, "status": status(config), "registration": registration}


@router.post("/api/ares/device/register")
def register_device(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_onboarding_mutation)],
):
    from api.ares_devices import register_device as register
    from api.config import get_config

    record = payload.get("device")
    with profile_scope(identity.profile):
        return register(record if isinstance(record, dict) else None, get_config())


@router.post("/api/ares/provider/sync")
def sync_provider_configuration(
    payload: dict[str, Any],
    identity: Annotated[RequestIdentity, Depends(require_onboarding_mutation)],
):
    from api.ares_provider_sync import sync_fallback_chain, sync_provider
    from api.config import _get_config_path

    targets = payload.get("targets") or ["ares", "jros"]
    if not isinstance(targets, list):
        raise CoreApiError(400, "targets must be a list of ares and/or jros")
    dry_run = bool(payload.get("dry_run", False))
    try:
        with profile_scope(identity.profile):
            config_path = _get_config_path()
            result = sync_provider(
                provider=str(payload.get("provider") or "").strip(),
                model=str(payload.get("model") or "").strip(),
                base_url=str(payload.get("base_url") or "").strip() or None,
                targets=targets,
                api_key_env=str(payload.get("api_key_env") or "").strip() or None,
                ares_config_path=config_path,
                dry_run=dry_run,
            )
            if "jros" in targets:
                try:
                    result["fallback_chain"] = sync_fallback_chain(
                        ares_config_path=config_path,
                        dry_run=dry_run,
                    )
                except Exception as exc:
                    result["fallback_chain"] = {"ok": False, "error": str(exc)}
    except ValueError as exc:
        raise CoreApiError(400, str(exc)) from exc
    except Exception as exc:
        raise CoreApiError(400, f"Failed to sync provider: {exc}") from exc
    return result


__all__ = ["router"]
