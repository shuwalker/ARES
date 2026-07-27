"""Transport-neutral chat and terminal operations for WebSocket routers."""

from __future__ import annotations

from typing import Any, NoReturn

from .adapters import AdapterError, AdapterRegistry, StreamSubscription
from .errors import CoreApiError
from .request_context import profile_scope
from .schemas import ChatStart, TerminalClose, TerminalInput, TerminalResize, TerminalStart


QueueSubscription = StreamSubscription


class RealtimeService:
    """Observe existing runtime state without becoming a second runtime owner."""

    def __init__(self, *, adapter_registry: AdapterRegistry | None = None) -> None:
        self.adapters = adapter_registry or AdapterRegistry()

    @staticmethod
    def _raise_adapter_error(exc: AdapterError) -> NoReturn:
        raise CoreApiError(
            exc.status_code,
            exc.message,
            code=exc.code,
            context=exc.context,
        ) from exc

    @staticmethod
    def _session_for_profile(session_id: str, profile: str | None):
        from api.models import get_session
        from api.profiles import _profiles_match, get_active_profile_name

        try:
            session = get_session(session_id)
            if getattr(session, "is_cli_session", False):
                from api.session_access import get_or_materialize_session

                session = get_or_materialize_session(
                    session_id,
                    refresh_cli_messages=True,
                )
        except KeyError:
            from api.session_access import get_or_materialize_session

            try:
                session = get_or_materialize_session(session_id)
            except KeyError as exc:
                raise CoreApiError(404, "Session not found") from exc
            except PermissionError as exc:
                raise CoreApiError(403, str(exc)) from exc
        active_profile = profile or get_active_profile_name()
        if not _profiles_match(getattr(session, "profile", None), active_profile):
            raise CoreApiError(404, "Session not found")
        return session

    async def start_chat(self, request: ChatStart, *, profile: str | None) -> dict[str, Any]:
        requested_profile = request.profile or profile
        if profile and request.profile and profile != request.profile:
            raise CoreApiError(409, "Requested profile does not match the active profile")
        with profile_scope(requested_profile):
            session = self._session_for_profile(request.session_id, requested_profile)
            if getattr(session, "read_only", False):
                raise CoreApiError(403, "This conversation is read-only")
            if request.workspace:
                from api.workspace import resolve_trusted_workspace

                try:
                    session.workspace = str(resolve_trusted_workspace(request.workspace))
                except ValueError as exc:
                    raise CoreApiError(400, str(exc)) from exc
            if request.model:
                session.model = request.model
            if request.model_provider:
                session.model_provider = request.model_provider
            try:
                if request.connection_id:
                    adapter = self.adapters.execution_adapter(request.connection_id)
                    session.ares_backend = adapter.adapter_id
                else:
                    adapter = self.adapters.for_session(session, profile=requested_profile)
                return await adapter.stream_chat(
                    request,
                    session=session,
                    profile=requested_profile,
                )
            except AdapterError as exc:
                self._raise_adapter_error(exc)

    def authorize_stream(self, stream_id: str, *, profile: str | None) -> str:
        from api.config import stream_owner_session_id
        from api.run_journal import find_run_summary

        owner = stream_owner_session_id(stream_id)
        if not owner:
            try:
                owner = str((find_run_summary(stream_id) or {}).get("session_id") or "")
            except ValueError:
                owner = ""
        if not owner:
            raise CoreApiError(404, "Stream not found")
        with profile_scope(profile):
            self._session_for_profile(owner, profile)
        return owner

    def chat_subscription(self, stream_id: str, *, profile: str | None) -> QueueSubscription | None:
        owner = self.authorize_stream(stream_id, profile=profile)
        with profile_scope(profile):
            session = self._session_for_profile(owner, profile)
            adapter = self.adapters.for_session(session, profile=profile)
            return adapter.subscribe_stream(stream_id, owner_session_id=owner)

    def replay_chat(
        self,
        stream_id: str,
        *,
        profile: str | None = None,
        after_event_id: str | None = None,
    ) -> list[dict[str, Any]]:
        owner = self.authorize_stream(stream_id, profile=profile)
        with profile_scope(profile):
            session = self._session_for_profile(owner, profile)
            adapter = self.adapters.for_session(session, profile=profile)
            return adapter.replay_stream(stream_id, after_event_id=after_event_id)

    def stream_status(self, stream_id: str, *, profile: str | None) -> dict[str, Any]:
        try:
            owner = self.authorize_stream(stream_id, profile=profile)
        except CoreApiError as exc:
            if exc.status_code == 404:
                return {"active": False, "stream_id": stream_id, "replay_available": False}
            raise
        with profile_scope(profile):
            session = self._session_for_profile(owner, profile)
            adapter = self.adapters.for_session(session, profile=profile)
            return adapter.stream_status(stream_id)

    def cancel_chat(self, stream_id: str, *, profile: str | None) -> dict[str, Any]:
        owner = self.authorize_stream(stream_id, profile=profile)
        with profile_scope(profile):
            session = self._session_for_profile(owner, profile)
            adapter = self.adapters.for_session(session, profile=profile)
            return {
                "ok": True,
                "cancelled": adapter.cancel_stream(stream_id),
                "stream_id": stream_id,
            }

    def session_activity_subscription(
        self,
        session_id: str,
        *,
        profile: str | None,
    ) -> QueueSubscription:
        with profile_scope(profile):
            self._session_for_profile(session_id, profile)
            from api.background_process import get_or_create_session_channel

            channel = get_or_create_session_channel(session_id)
            subscriber = channel.subscribe()
            return QueueSubscription(channel, subscriber, {}, session_id)

    def session_snapshot(self, session_id: str, *, profile: str | None) -> dict[str, Any]:
        """Return the bounded session projection used as a replay recovery boundary."""

        with profile_scope(profile):
            session = self._session_for_profile(session_id, profile)
            from api.helpers import redact_session_data

            return redact_session_data(session.compact())

    def start_terminal(self, request: TerminalStart, *, profile: str | None) -> dict[str, Any]:
        with profile_scope(profile):
            session = self._session_for_profile(request.session_id, profile)
            from api.config import get_config
            from api.terminal import start_terminal
            from api.workspace import _is_remote_terminal_backend, resolve_trusted_workspace

            if _is_remote_terminal_backend(get_config().get("terminal", {})):
                raise CoreApiError(
                    400,
                    "Embedded terminal is only supported for local terminal backends.",
                    code="remote_terminal_backend_unsupported",
                )
            try:
                workspace = resolve_trusted_workspace(getattr(session, "workspace", "") or "")
                terminal = start_terminal(
                    request.session_id,
                    workspace,
                    rows=request.rows,
                    cols=request.cols,
                    restart=request.restart,
                )
            except KeyError as exc:
                raise CoreApiError(404, str(exc)) from exc
            except (ValueError, NotImplementedError) as exc:
                raise CoreApiError(400, str(exc)) from exc
            return {
                "ok": True,
                "session_id": request.session_id,
                "workspace": terminal.workspace,
                "running": terminal.is_alive(),
            }

    def terminal_input(self, request: TerminalInput, *, profile: str | None) -> dict[str, Any]:
        with profile_scope(profile):
            self._session_for_profile(request.session_id, profile)
            from api.terminal import write_terminal

            try:
                write_terminal(request.session_id, request.data)
            except KeyError as exc:
                raise CoreApiError(404, str(exc)) from exc
            return {"ok": True}

    def close_terminal(self, request: TerminalClose, *, profile: str | None) -> dict[str, Any]:
        with profile_scope(profile):
            self._session_for_profile(request.session_id, profile)
            from api.terminal import close_terminal

            return {"ok": True, "closed": close_terminal(request.session_id)}

    def resize_terminal(self, request: TerminalResize, *, profile: str | None) -> dict[str, Any]:
        with profile_scope(profile):
            self._session_for_profile(request.session_id, profile)
            from api.terminal import resize_terminal

            try:
                resize_terminal(request.session_id, request.rows, request.cols)
            except KeyError as exc:
                raise CoreApiError(404, str(exc)) from exc
            return {"ok": True}

    def terminal_queue(self, session_id: str, *, profile: str | None):
        with profile_scope(profile):
            self._session_for_profile(session_id, profile)
            from api.terminal import get_terminal

            terminal = get_terminal(session_id)
            if terminal is None:
                raise CoreApiError(404, "Terminal not running")
            return terminal
