"""Framework-independent operations used by the Step 2 FastAPI routers.

The service calls existing ARES domain modules directly.  It does not invoke
the legacy HTTP dispatcher, construct fake request handlers, or translate
through HTTP.
"""

from __future__ import annotations

import os
import sqlite3
import threading
import time
from pathlib import Path
from typing import Any

from .errors import CoreApiError
from .request_context import profile_scope
from .schemas import SessionCreate, SettingsUpdate


class AresCoreService:
    def __init__(self) -> None:
        self.started_at = time.time()

    def health(self, *, deep: bool = False) -> tuple[dict[str, Any], int]:
        from api import config as live_config
        from api.config import STREAMS, STREAMS_LOCK
        from api.models import SESSIONS

        now = time.time()
        with STREAMS_LOCK:
            active_streams = len(STREAMS)
        with live_config.ACTIVE_RUNS_LOCK:
            runs = []
            for raw in (live_config.ACTIVE_RUNS or {}).values():
                item = dict(raw or {})
                item.pop("session_id", None)
                item.pop("stream_id", None)
                item.pop("workspace", None)
                try:
                    item["age_seconds"] = round(max(0.0, now - float(item.get("started_at") or now)), 1)
                except (TypeError, ValueError):
                    item["age_seconds"] = 0.0
                runs.append(item)
            last_finished = live_config.LAST_RUN_FINISHED_AT
        runs.sort(key=lambda item: float(item.get("started_at") or 0.0))

        si_on = False
        try:
            from api.si.bridge import si_enabled as _si_enabled

            si_on = bool(_si_enabled())
        except Exception:
            si_on = False

        payload: dict[str, Any] = {
            "status": "ok",
            "sessions": len(SESSIONS),
            "active_streams": active_streams,
            "active_runs": len(runs),
            "runs": runs,
            "last_run_finished_at": last_finished,
            "server_started_at": self.started_at,
            "uptime_seconds": round(time.time() - self.started_at, 1),
            "accept_loop": {"status": "ok", "server": "uvicorn"},
            "si_enabled": si_on,
            "role": os.environ.get("ARES_ROLE") or "primary",
        }
        if runs:
            payload["oldest_run_age_seconds"] = runs[0]["age_seconds"]
        elif last_finished:
            payload["idle_seconds_since_last_run"] = round(max(0.0, now - float(last_finished)), 1)
        if deep:
            from api.models import _active_state_db_path, all_sessions, load_projects

            checks: dict[str, Any] = {
                "streams_lock": {"status": "ok", "active_streams": active_streams},
            }
            try:
                checks["sessions"] = {"status": "ok", "count": len(all_sessions())}
            except Exception as exc:
                checks["sessions"] = {"status": "error", "error": type(exc).__name__}
                payload["status"] = "degraded"
            try:
                checks["projects"] = {"status": "ok", "count": len(load_projects())}
            except Exception as exc:
                checks["projects"] = {"status": "error", "error": type(exc).__name__}
                payload["status"] = "degraded"
            try:
                state_db = _active_state_db_path()
                if not state_db or not Path(state_db).exists():
                    checks["state_db"] = {"status": "missing"}
                else:
                    with sqlite3.connect(str(state_db)) as connection:
                        connection.execute("SELECT 1").fetchone()
                    checks["state_db"] = {"status": "ok"}
            except Exception as exc:
                checks["state_db"] = {"status": "error", "error": type(exc).__name__}
                payload["status"] = "degraded"
            try:
                from api.si.identity import load_identity
                from api.si.bridge import si_enabled as _si_enabled

                identity = load_identity()
                enabled = bool(_si_enabled())
                checks["si"] = {
                    "status": "ok" if enabled else "disabled",
                    "enabled": enabled,
                    "identity_name": identity.name,
                    "continuity_dir": os.environ.get("ARES_CONTINUITY_DIR") or "",
                }
            except Exception as exc:
                checks["si"] = {"status": "error", "error": type(exc).__name__}
            payload["checks"] = checks
        status_code = 200 if payload["status"] == "ok" else 503
        return payload, status_code

    def agent_health(self) -> dict[str, Any]:
        from api.agent_health import build_agent_health_payload
        from api.gateway_chat import gateway_chat_config_status

        payload = build_agent_health_payload()
        payload["gateway_chat"] = gateway_chat_config_status()
        return payload

    def settings(self, *, profile: str | None) -> dict[str, Any]:
        with profile_scope(profile):
            from api.auth import get_password_hash, is_auth_enabled
            from api.config import (
                get_max_tokens_status,
                load_settings,
                persisted_speech_settings_keys,
            )

            settings = load_settings()
            settings["persisted_speech_keys"] = persisted_speech_settings_keys()
            settings.pop("password_hash", None)
            try:
                settings.update(get_max_tokens_status())
            except Exception:
                settings.update(
                    max_tokens=None,
                    max_tokens_effective=None,
                    max_tokens_fallback=None,
                )
            settings["password_env_var"] = bool(os.getenv("ARES_WEBUI_PASSWORD", "").strip())
            settings["auth_enabled"] = is_auth_enabled()
            settings["password_auth_enabled"] = get_password_hash() is not None
            settings.setdefault("passkeys_enabled", False)
            settings.setdefault("passwordless_enabled", False)
            try:
                from api.auth import _passkey_feature_flag_enabled
                from api.passkeys import registered_credentials

                credentials = registered_credentials() if _passkey_feature_flag_enabled() else []
                settings["passkeys_enabled"] = bool(credentials)
                settings["passwordless_enabled"] = bool(credentials) and not settings["password_auth_enabled"]
            except Exception:
                pass
            try:
                from api.updates import AGENT_VERSION, WEBUI_VERSION, _read_update_channel, channel_version_badge

                settings["webui_version"] = WEBUI_VERSION
                settings["agent_version"] = AGENT_VERSION
                channel = _read_update_channel()
                settings["update_channel"] = channel
                settings["update_channel_version"] = channel_version_badge(channel)
            except Exception:
                settings.setdefault("webui_version", None)
            return settings

    def update_settings(
        self,
        update: SettingsUpdate,
        *,
        profile: str | None,
    ) -> dict[str, Any]:
        with profile_scope(profile):
            from api.config import save_settings

            save_settings(update.model_dump(exclude_unset=True))
        return self.settings(profile=profile)

    def sessions(
        self,
        *,
        profile: str | None,
        exclude_hidden: bool,
        include_archived: bool,
    ) -> dict[str, Any]:
        with profile_scope(profile):
            from api.config import load_settings
            from api.models import all_sessions, get_cli_sessions
            from api.profiles import _profiles_match, get_active_profile_name
            from api.session_runtime_state import reconcile_stale_stream_state_for_session_rows

            active_profile = profile or get_active_profile_name()
            rows = list(all_sessions())
            if reconcile_stale_stream_state_for_session_rows(rows):
                rows = list(all_sessions())
            settings = load_settings()
            cli_rows: list[dict] = []
            if settings.get("show_cli_sessions"):
                from api.session_listing import (
                    is_duplicate_webui_state_projection,
                    prune_orphaned_agent_sidecars,
                    session_lineage_ids,
                )

                represented = set()
                for row in rows:
                    represented.update(session_lineage_ids(row))
                cli_rows = [
                    row
                    for row in get_cli_sessions(
                        source_filter=settings.get("agent_session_source_filter"),
                        all_profiles=False,
                    )
                    if not is_duplicate_webui_state_projection(row, represented)
                ]
                rows = prune_orphaned_agent_sidecars(rows, cli_rows)
            from api.session_listing import prune_orphaned_webui_zero_message_sessions

            rows = prune_orphaned_webui_zero_message_sessions(rows)
            # Imported projections are merged first so a persisted sidecar wins
            # on equal session_id (notably archived cron/webhook conversations).
            rows = cli_rows + rows
            deduped = {}
            for row in rows:
                if not isinstance(row, dict):
                    continue
                session_id = str(row.get("session_id") or "")
                if session_id:
                    deduped[session_id] = row
            rows = [
                row
                for row in deduped.values()
                if _profiles_match(row.get("profile"), active_profile)
            ]
            archived_count = sum(1 for row in rows if row.get("archived"))
            if not include_archived:
                rows = [row for row in rows if not row.get("archived")]
            if exclude_hidden:
                rows = [
                    row
                    for row in rows
                    if not row.get("pre_compression_snapshot")
                    and str(row.get("source_tag") or "") not in {"cron", "webhook"}
                ]
            rows.sort(
                key=lambda row: (
                    bool(row.get("pinned")),
                    float(row.get("last_message_at") or row.get("updated_at") or 0),
                ),
                reverse=True,
            )
            from api.helpers import redact_session_rows

            rows = redact_session_rows(rows)
            return {
                "sessions": rows,
                "active_profile": active_profile,
                "all_profiles": False,
                "other_profile_count": 0,
                "archived_count": archived_count,
            }

    def session(
        self,
        session_id: str,
        *,
        profile: str | None,
        load_messages: bool,
        message_limit: int | None,
        message_before: int | None = None,
        resolve_model: bool = True,
    ) -> dict[str, Any]:
        with profile_scope(profile):
            from api.models import get_session
            from api.profiles import _profiles_match, get_active_profile_name

            try:
                session = get_session(session_id, metadata_only=not load_messages)
            except KeyError as exc:
                from api.session_access import claim_or_synthesize_cli_session

                session, _reason = claim_or_synthesize_cli_session(session_id)
                if session is None:
                    raise CoreApiError(404, "Session not found") from exc
            from api.session_runtime_state import clear_stale_stream_state

            clear_stale_stream_state(session)
            active_profile = profile or get_active_profile_name()
            session_profile = getattr(session, "profile", None)
            if not _profiles_match(session_profile, active_profile):
                raise CoreApiError(
                    409,
                    "Session belongs to a different profile",
                    code="session_profile_mismatch",
                    context={"session_id": session_id, "profile": session_profile},
                )
            from api.session_projection import project_session_detail

            payload = project_session_detail(
                session,
                load_messages=load_messages,
                message_limit=message_limit,
                message_before=message_before,
                resolve_model=resolve_model,
            )
            from api.helpers import redact_session_data

            return {"session": redact_session_data(payload)}

    def create_session(
        self,
        request: SessionCreate,
        *,
        profile: str | None,
    ) -> dict[str, Any]:
        requested_profile = request.profile or profile
        if profile and request.profile and profile != request.profile:
            raise CoreApiError(409, "Requested profile does not match the active profile")
        with profile_scope(requested_profile):
            from api.models import get_session, new_session
            from api.profiles import _profiles_match, get_active_profile_name
            from api.workspace import resolve_trusted_workspace

            previous_session_id = request.prev_session_id
            if previous_session_id:
                try:
                    previous = get_session(previous_session_id, metadata_only=True)
                    active_profile = requested_profile or get_active_profile_name()
                    if not _profiles_match(getattr(previous, "profile", None), active_profile):
                        previous_session_id = None
                except KeyError:
                    previous_session_id = None
            if previous_session_id:
                self._commit_previous_session(previous_session_id, requested_profile)

            workspace = None
            requested_workspace = request.workspace
            if request.worktree and not requested_workspace:
                from api.workspace import get_last_workspace

                requested_workspace = get_last_workspace()
            if requested_workspace:
                try:
                    workspace = str(resolve_trusted_workspace(requested_workspace))
                except (TypeError, ValueError) as exc:
                    raise CoreApiError(400, str(exc)) from exc
            worktree_info = None
            if request.worktree:
                if not workspace:
                    raise CoreApiError(400, "A workspace is required to create a worktree")
                try:
                    from api.worktrees import create_worktree_for_workspace

                    worktree_info = create_worktree_for_workspace(workspace)
                    workspace = str(Path(worktree_info["path"]).expanduser().resolve())
                except (KeyError, TypeError, ValueError, RuntimeError) as exc:
                    raise CoreApiError(400, str(exc)) from exc
            session = new_session(
                workspace=workspace,
                model=request.model,
                model_provider=request.model_provider,
                profile=requested_profile,
                project_id=request.project_id,
                enabled_toolsets=request.enabled_toolsets,
                worktree_info=worktree_info,
            )
            return {"session": session.compact() | {"messages": list(session.messages)}}

    @staticmethod
    def _commit_previous_session(session_id: str, profile: str | None) -> None:
        """Preserve the legacy non-blocking memory lifecycle on New Session."""

        def commit() -> None:
            with profile_scope(profile):
                try:
                    from api.session_lifecycle import commit_session_memory

                    commit_session_memory(session_id)
                except Exception:
                    # New-session creation must remain available when a runtime or
                    # memory provider is disconnected.
                    return

        threading.Thread(
            target=commit,
            daemon=True,
            name=f"commit-memory-{session_id}",
        ).start()

    def workspaces(self, *, profile: str | None) -> dict[str, Any]:
        with profile_scope(profile):
            from api.config import get_config
            from api.workspace import _is_remote_terminal_backend, get_last_workspace, load_workspaces

            terminal_config = get_config().get("terminal", {})
            return {
                "workspaces": load_workspaces(),
                "last": get_last_workspace(),
                "terminal_remote_backend": _is_remote_terminal_backend(terminal_config),
            }

    def list_workspace(
        self,
        session_id: str,
        relative_path: str,
        *,
        profile: str | None,
    ) -> dict[str, Any]:
        with profile_scope(profile):
            from api.models import get_session_for_file_ops
            from api.workspace import dir_signature, list_dir

            try:
                session = get_session_for_file_ops(session_id)
            except KeyError as exc:
                raise CoreApiError(404, "Session not found") from exc
            workspace = Path(session.workspace)
            try:
                entries = list_dir(workspace, relative_path)
            except (FileNotFoundError, ValueError) as exc:
                raise CoreApiError(404, str(exc)) from exc
            return {
                "entries": entries,
                "signature": dir_signature(workspace, relative_path, entries),
                "path": relative_path,
            }
