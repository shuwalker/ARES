"""Server-initiated turn policy, independent of HTTP and WebSocket transports."""

from __future__ import annotations

import logging

from api.config import PENDING_BG_TASK_COMPLETIONS, canonical_model_provider_lane, _get_session_agent_lock
from api.model_resolution import _read_profile_model_config, _resolve_compatible_session_model_state
from api.models import (
    PROCESS_WAKEUP_PAUSE_ERROR,
    clear_process_wakeup_pause,
    clear_process_wakeup_pause_if_model_changed,
    get_session,
    process_wakeup_credential_state_fingerprint,
    process_wakeup_pause_credential_state_changed,
    process_wakeup_pause_matches,
    suppress_process_wakeup_for_provider_pause,
)
from api.providers import provider_has_process_wakeup_recovery_credential
from api.chat_runtime import resolve_chat_workspace_with_recovery as _resolve_chat_workspace_with_recovery


logger = logging.getLogger(__name__)


def _process_wakeup_revalidation_provider(model, provider) -> str:
    try:
        _model, resolved = canonical_model_provider_lane(model, provider)
    except Exception:
        resolved = None
    return str(resolved or provider or "").strip()


def _process_wakeup_provider_has_recovery_credential(
    session,
    *,
    model,
    provider,
    provider_id: str | None = None,
) -> bool:
    provider_id = str(provider_id or _process_wakeup_revalidation_provider(model, provider)).strip()
    if not provider_id:
        return False
    profile = str(getattr(session, "profile", "") or "").strip()
    if profile:
        from api.profiles import _is_root_profile, profile_scope_for_detached_worker

        if not _is_root_profile(profile):
            with profile_scope_for_detached_worker(
                profile,
                "process_wakeup credential revalidation",
                logger_override=logger,
            ):
                return provider_has_process_wakeup_recovery_credential(provider_id, refresh=True)
    return provider_has_process_wakeup_recovery_credential(provider_id, refresh=True)


def _refresh_process_wakeup_pause_credential_fingerprint(session) -> bool:
    pause = getattr(session, "process_wakeup_pause", None)
    if not isinstance(pause, dict) or not pause.get("paused"):
        return False
    updated = dict(pause)
    updated["credential_state_fingerprint"] = process_wakeup_credential_state_fingerprint(session)
    session.process_wakeup_pause = updated
    return True


def _start_run(session, **kwargs):
    """Default bridge to the framework-neutral worker launcher."""
    from api.chat_runtime import start_session_turn as start

    return start(
        session.session_id,
        kwargs.get("msg", ""),
        source=kwargs.get("source", "process_wakeup"),
        workspace=kwargs.get("workspace"),
        model=kwargs.get("model"),
        model_provider=kwargs.get("model_provider"),
        _skip_wakeup_policy=True,
    )


def start_session_turn(session_id: str, message: str, *, source: str = "process_wakeup") -> dict:
    """Resolve a server-side turn and enforce the persisted wakeup-pause policy."""
    message = str(message or "").strip()
    if not message:
        return {"error": "message is required", "_status": 400}
    try:
        session = get_session(session_id)
    except KeyError:
        return {"error": "Session not found", "_status": 404}
    try:
        workspace = _resolve_chat_workspace_with_recovery(session, None)
    except ValueError as exc:
        return {"error": str(exc), "_status": 400}

    requested_model = getattr(session, "model", None)
    requested_provider = getattr(session, "model_provider", None)
    profile_provider, profile_default, profile_config = _read_profile_model_config(
        session,
        requested_provider,
    )
    model, provider, normalized = _resolve_compatible_session_model_state(
        requested_model,
        requested_provider,
        profile_provider=profile_provider,
        profile_default_model=profile_default,
        profile_config=profile_config,
        prefer_cached_catalog=True,
    )

    paused_response = None
    with _get_session_agent_lock(session.session_id):
        try:
            session = get_session(session_id)
        except KeyError:
            return {"error": "Session not found", "_status": 404}
        if clear_process_wakeup_pause_if_model_changed(session, model=model, provider=provider):
            session.save(touch_updated_at=False)
        if source == "process_wakeup":
            try:
                credential_changed = process_wakeup_pause_credential_state_changed(session)
            except Exception:
                credential_changed = False
            if process_wakeup_pause_matches(
                session,
                model=model,
                provider=provider,
                classification="credential_pool_empty",
            ):
                recovered = _process_wakeup_provider_has_recovery_credential(
                    session,
                    model=model,
                    provider=provider,
                )
                if recovered:
                    clear_process_wakeup_pause(
                        session,
                        reason="credential_state_changed" if credential_changed else "credential_recovered",
                    )
                    session.save(touch_updated_at=False)
                elif credential_changed and _refresh_process_wakeup_pause_credential_fingerprint(session):
                    session.save(touch_updated_at=False)
            pause = suppress_process_wakeup_for_provider_pause(
                session,
                model=model,
                provider=provider,
                classification="credential_pool_empty",
            )
            if pause is not None:
                PENDING_BG_TASK_COMPLETIONS.discard(session.session_id)
                session.save(touch_updated_at=False)
                paused_response = {
                    "error": PROCESS_WAKEUP_PAUSE_ERROR,
                    "message": (
                        "Automatic process wakeups are paused for this session because "
                        "the provider credential pool is unavailable."
                    ),
                    "process_wakeup_pause": pause,
                    "_status": 409,
                }
    if paused_response is not None:
        return paused_response
    return _start_run(
        session,
        msg=message,
        attachments=[],
        workspace=workspace,
        model=model,
        model_provider=provider,
        normalized_model=normalized,
        source=source,
        route="start_session_turn",
    )


__all__ = ["start_session_turn"]
