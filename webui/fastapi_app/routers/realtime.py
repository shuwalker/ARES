"""Chat, activity, and terminal WebSocket transports."""

from __future__ import annotations

import asyncio
import json
import queue
from typing import Annotated, Any

from fastapi import APIRouter, Depends, Header, Query, WebSocket, WebSocketDisconnect
from fastapi.encoders import jsonable_encoder
from fastapi.responses import StreamingResponse

from ..dependencies import get_realtime_service
from ..errors import CoreApiError
from ..realtime import QueueSubscription, RealtimeService
from ..request_context import (
    RequestIdentity,
    connection_is_local_or_authenticated,
    require_identity,
    require_mutation_identity,
    require_terminal_identity,
    websocket_identity,
)
from ..schemas import (
    ChatStart,
    ChatStartResponse,
    ChatStatusResponse,
    TerminalClose,
    TerminalInput,
    TerminalResize,
    TerminalStart,
)


router = APIRouter(tags=["realtime"])
_HEARTBEAT_SECONDS = 5.0
_TERMINAL_EVENTS = {"stream_end", "error", "cancel"}


def _event_envelope(
    event: str,
    data: Any,
    *,
    stream_id: str | None = None,
    session_id: str | None = None,
    event_id: str | None = None,
) -> dict[str, Any]:
    seq = None
    if event_id and ":" in event_id:
        try:
            seq = int(event_id.rsplit(":", 1)[-1])
        except ValueError:
            seq = None
    return {
        "schema_version": 1,
        "event": event,
        "data": jsonable_encoder(data),
        "event_id": event_id,
        "seq": seq,
        "stream_id": stream_id,
        "session_id": session_id,
        "terminal": event in _TERMINAL_EVENTS,
    }


async def _accept_websocket(websocket: WebSocket) -> RequestIdentity | None:
    try:
        identity = websocket_identity(websocket)
    except CoreApiError as exc:
        await websocket.close(code=4403 if exc.status_code == 403 else 4401, reason=exc.message)
        return None
    protocols = str(websocket.headers.get("sec-websocket-protocol") or "")
    selected_protocol = "ares-v1" if "ares-v1" in {item.strip() for item in protocols.split(",")} else None
    await websocket.accept(subprotocol=selected_protocol)
    return identity


async def _send_error_and_close(websocket: WebSocket, exc: CoreApiError) -> None:
    await websocket.send_json(_event_envelope("error", exc.payload()))
    await websocket.close(code=4400 + min(max(exc.status_code, 0), 99), reason=exc.message[:120])


async def _queue_get(subscriber: queue.Queue):
    return await asyncio.to_thread(subscriber.get, True, _HEARTBEAT_SECONDS)


def _sse_frame(event: str, data: Any, event_id: str | None = None) -> bytes:
    lines = []
    if event_id:
        lines.append(f"id: {event_id}")
    lines.append(f"event: {event}")
    lines.append(
        "data: "
        + json.dumps(jsonable_encoder(data), ensure_ascii=False, separators=(",", ":"))
    )
    return ("\n".join(lines) + "\n\n").encode()


def _sse_response(generator) -> StreamingResponse:
    return StreamingResponse(
        generator,
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )


@router.post("/api/chat/start", response_model=ChatStartResponse)
async def start_chat(
    request: ChatStart,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[RealtimeService, Depends(get_realtime_service)],
):
    return await service.start_chat(request, profile=identity.profile)


@router.get("/api/chat/stream/status", response_model=ChatStatusResponse)
def chat_status(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[RealtimeService, Depends(get_realtime_service)],
    stream_id: str = Query(min_length=1, max_length=256),
):
    return service.stream_status(stream_id, profile=identity.profile)


@router.get("/api/chat/cancel")
@router.post("/api/chat/cancel")
def cancel_chat(
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[RealtimeService, Depends(get_realtime_service)],
    stream_id: str = Query(min_length=1, max_length=256),
):
    return service.cancel_chat(stream_id, profile=identity.profile)


@router.post("/api/chat", response_model=ChatStartResponse)
async def legacy_chat(
    request: ChatStart,
    identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
    service: Annotated[RealtimeService, Depends(get_realtime_service)],
):
    """Compatibility alias; streaming remains the canonical response model."""
    return await service.start_chat(request, profile=identity.profile)


@router.post("/api/chat/steer")
def steer_chat(
    payload: dict[str, Any],
    _identity: Annotated[RequestIdentity, Depends(require_mutation_identity)],
):
    from api.chat_control import ChatControlError, steer_session

    try:
        return steer_session(payload)
    except ChatControlError as exc:
        raise CoreApiError(exc.status_code, str(exc)) from exc


@router.websocket("/api/chat/stream")
async def chat_stream(websocket: WebSocket):
    identity = await _accept_websocket(websocket)
    if identity is None:
        return
    service: RealtimeService = websocket.app.state.realtime_service
    stream_id = str(websocket.query_params.get("stream_id") or "").strip()
    after_event_id = str(websocket.query_params.get("after_event_id") or "").strip() or None
    if not stream_id:
        await _send_error_and_close(websocket, CoreApiError(400, "stream_id is required"))
        return

    subscription: QueueSubscription | None = None
    sent_ids: set[str] = set()
    try:
        subscription = await asyncio.to_thread(
            service.chat_subscription,
            stream_id,
            profile=identity.profile,
        )
        owner = (
            subscription.owner_session_id
            if subscription is not None
            else await asyncio.to_thread(
                service.authorize_stream,
                stream_id,
                profile=identity.profile,
            )
        )
        from api.stream_recovery import assess_offline_gap, recovery_payload

        replay_safe, client_seq, dropped = await asyncio.to_thread(
            assess_offline_gap,
            stream_id,
            after_event_id,
            subscription.snapshot if subscription is not None else {},
        )
        if not replay_safe:
            await websocket.send_json(
                _event_envelope(
                    "apperror",
                    recovery_payload(stream_id, owner, dropped),
                    stream_id=stream_id,
                    session_id=owner,
                )
            )
            await websocket.close(code=1000)
            return
        replay = await asyncio.to_thread(
            service.replay_chat,
            stream_id,
            profile=identity.profile,
            after_event_id=after_event_id,
        )
        replay_terminal = False
        for entry in replay:
            event = str(entry.get("event") or entry.get("type") or "message")
            event_id = str(entry.get("event_id") or "") or None
            if event_id and event_id in sent_ids:
                continue
            await websocket.send_json(
                _event_envelope(
                    event,
                    entry.get("payload", entry),
                    stream_id=stream_id,
                    session_id=owner,
                    event_id=event_id,
                )
            )
            if event_id:
                sent_ids.add(event_id)
            replay_terminal = replay_terminal or event in _TERMINAL_EVENTS

        # A durable terminal event is authoritative.  Do not wait on a live
        # queue after replay has already established that the run ended; this
        # also prevents a reconnect from hanging when the channel outlives its
        # completed journal briefly during cleanup.
        if replay_terminal:
            await websocket.close(code=1000)
            return

        if subscription is None:
            await websocket.send_json(
                _event_envelope(
                    "stream_end",
                    {"status": "not_active"},
                    stream_id=stream_id,
                    session_id=owner,
                )
            )
            await websocket.close(code=1000)
            return

        while True:
            try:
                item = await _queue_get(subscription.subscriber)
            except queue.Empty:
                await websocket.send_json(
                    _event_envelope(
                        "heartbeat",
                        {"status": "connected"},
                        stream_id=stream_id,
                        session_id=owner,
                    )
                )
                continue
            event = str(item[0] if len(item) >= 1 else "message")
            data = item[1] if len(item) >= 2 else {}
            event_id = str(item[2] or "") if len(item) >= 3 else None
            if client_seq is not None and event_id:
                from api.stream_recovery import same_run_sequence

                item_seq = same_run_sequence(event_id, stream_id)
                if item_seq is not None and item_seq <= client_seq:
                    if event in _TERMINAL_EVENTS:
                        break
                    continue
            if event_id and event_id in sent_ids:
                if event in _TERMINAL_EVENTS:
                    break
                continue
            await websocket.send_json(
                _event_envelope(
                    event,
                    data,
                    stream_id=stream_id,
                    session_id=owner,
                    event_id=event_id,
                )
            )
            if event_id:
                sent_ids.add(event_id)
            if event in _TERMINAL_EVENTS:
                break
    except CoreApiError as exc:
        await _send_error_and_close(websocket, exc)
    except (WebSocketDisconnect, RuntimeError):
        pass
    finally:
        if subscription is not None:
            subscription.close()


@router.get("/api/chat/stream")
async def chat_stream_sse(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[RealtimeService, Depends(get_realtime_service)],
    stream_id: str = Query(min_length=1, max_length=256),
    after_event_id: str | None = Query(default=None, max_length=256),
):
    """Compatibility transport for pre-WebSocket clients."""
    subscription = await asyncio.to_thread(
        service.chat_subscription,
        stream_id,
        profile=identity.profile,
    )
    if subscription is None:
        await asyncio.to_thread(service.authorize_stream, stream_id, profile=identity.profile)
    owner = (
        subscription.owner_session_id
        if subscription is not None
        else await asyncio.to_thread(service.authorize_stream, stream_id, profile=identity.profile)
    )
    from api.stream_recovery import assess_offline_gap, recovery_payload

    replay_safe, client_seq, dropped = await asyncio.to_thread(
        assess_offline_gap,
        stream_id,
        after_event_id,
        subscription.snapshot if subscription is not None else {},
    )
    replay = await asyncio.to_thread(
        service.replay_chat,
        stream_id,
        profile=identity.profile,
        after_event_id=after_event_id,
    )

    async def events():
        sent_ids: set[str] = set()
        try:
            if not replay_safe:
                yield _sse_frame(
                    "apperror",
                    recovery_payload(stream_id, owner, dropped),
                )
                return
            terminal = False
            for entry in replay:
                event = str(entry.get("event") or entry.get("type") or "message")
                event_id = str(entry.get("event_id") or "") or None
                if event_id and event_id in sent_ids:
                    continue
                yield _sse_frame(event, entry.get("payload", entry), event_id)
                if event_id:
                    sent_ids.add(event_id)
                terminal = terminal or event in _TERMINAL_EVENTS
            if terminal:
                return
            if subscription is None:
                yield _sse_frame("stream_end", {"status": "not_active"})
                return
            while True:
                try:
                    item = await _queue_get(subscription.subscriber)
                except queue.Empty:
                    yield b": heartbeat\n\n"
                    continue
                event = str(item[0] if len(item) >= 1 else "message")
                data = item[1] if len(item) >= 2 else {}
                event_id = str(item[2] or "") if len(item) >= 3 else None
                if client_seq is not None and event_id:
                    from api.stream_recovery import same_run_sequence

                    item_seq = same_run_sequence(event_id, stream_id)
                    if item_seq is not None and item_seq <= client_seq:
                        if event in _TERMINAL_EVENTS:
                            return
                        continue
                if not event_id or event_id not in sent_ids:
                    yield _sse_frame(event, data, event_id)
                    if event_id:
                        sent_ids.add(event_id)
                if event in _TERMINAL_EVENTS:
                    return
        finally:
            if subscription is not None:
                subscription.close()

    return _sse_response(events())


@router.websocket("/api/sessions/{session_id}/stream")
async def session_activity(websocket: WebSocket, session_id: str):
    identity = await _accept_websocket(websocket)
    if identity is None:
        return
    service: RealtimeService = websocket.app.state.realtime_service
    subscription = None
    try:
        subscription = await asyncio.to_thread(
            service.session_activity_subscription,
            session_id,
            profile=identity.profile,
        )
        while True:
            try:
                event, data = await _queue_get(subscription.subscriber)
            except queue.Empty:
                await websocket.send_json(
                    _event_envelope("heartbeat", {"status": "connected"}, session_id=session_id)
                )
                continue
            await websocket.send_json(_event_envelope(str(event), data, session_id=session_id))
    except CoreApiError as exc:
        await _send_error_and_close(websocket, exc)
    except (WebSocketDisconnect, RuntimeError):
        pass
    finally:
        if subscription is not None:
            subscription.close()


async def _session_activity_sse_response(
    service: RealtimeService,
    session_id: str,
    profile: str | None,
    *,
    after_event_id: str | None = None,
):
    subscription = await asyncio.to_thread(
        service.session_activity_subscription,
        session_id,
        profile=profile,
    )
    snapshot = await asyncio.to_thread(
        service.session_snapshot,
        session_id,
        profile=profile,
    )

    async def events():
        try:
            from api.run_journal import read_session_run_events

            replay = await asyncio.to_thread(
                read_session_run_events,
                session_id,
                after_event_id=after_event_id,
            )
            replay_status = str(replay.get("status") or "ok")
            if after_event_id and replay_status != "ok":
                # A cursor is opaque and session-bound.  Never guess at a
                # partial suffix when it is malformed, foreign, or evicted.
                yield _sse_frame(
                    "session_snapshot",
                    {
                        "session_id": session_id,
                        "reason": replay_status,
                        "cursor": after_event_id,
                        "session": snapshot,
                    },
                )
            else:
                yield _sse_frame(
                    "initial",
                    {
                        "session_id": session_id,
                        "replay_status": replay_status,
                        "cursor": after_event_id,
                    },
                )
                for entry in replay.get("events") or []:
                    if not isinstance(entry, dict):
                        continue
                    yield _sse_frame(
                        str(entry.get("event") or entry.get("type") or "message"),
                        entry.get("payload", entry),
                        str(entry.get("event_id") or "") or None,
                    )
            while True:
                try:
                    event, data = await _queue_get(subscription.subscriber)
                except queue.Empty:
                    yield b": keepalive\n\n"
                    continue
                yield _sse_frame(str(event), data)
        finally:
            subscription.close()

    return _sse_response(events())


@router.get("/api/session/stream")
async def legacy_session_activity_sse(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[RealtimeService, Depends(get_realtime_service)],
    session_id: str = Query(min_length=1, max_length=256),
):
    return await _session_activity_sse_response(service, session_id, identity.profile)


@router.get("/api/sessions/{session_id}/events")
async def session_activity_events_sse(
    session_id: str,
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[RealtimeService, Depends(get_realtime_service)],
    after_event_id: str | None = Query(default=None, max_length=256),
    last_event_id: str | None = Header(default=None, alias="Last-Event-ID"),
):
    cursor = str(last_event_id or "").strip() or str(after_event_id or "").strip() or None
    return await _session_activity_sse_response(
        service,
        session_id,
        identity.profile,
        after_event_id=cursor,
    )


@router.get("/api/sessions/events")
async def session_list_events_sse(
    _identity: Annotated[RequestIdentity, Depends(require_identity)],
):
    from api.session_events import subscribe_session_events, unsubscribe_session_events

    subscriber = subscribe_session_events()

    async def events():
        try:
            while True:
                try:
                    payload = await _queue_get(subscriber)
                except queue.Empty:
                    yield b": keepalive\n\n"
                    continue
                yield _sse_frame(str(payload.get("type") or "sessions_changed"), payload)
        finally:
            unsubscribe_session_events(subscriber)

    return _sse_response(events())


@router.get("/api/sessions/gateway/stream")
async def gateway_sessions_sse(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    probe: bool = Query(default=False),
):
    from api.config import load_settings
    from api.gateway_watcher import get_watcher
    from api.models import get_cli_sessions

    settings = load_settings()
    enabled = bool(settings.get("show_cli_sessions"))
    watcher = get_watcher(profile_name=identity.profile or "default")
    alive = bool(watcher and watcher.is_alive())
    if probe:
        payload = {
            "enabled": enabled,
            "fallback_poll_ms": 30_000,
            "ok": enabled and alive,
            "watcher_running": alive,
        }
        if not enabled:
            raise CoreApiError(404, "agent sessions not enabled", context=payload)
        if not alive:
            raise CoreApiError(503, "watcher not started", context=payload)
        return payload
    if not enabled:
        raise CoreApiError(404, "agent sessions not enabled")
    if not alive:
        raise CoreApiError(503, "watcher not started")
    subscriber = watcher.subscribe()

    async def events():
        try:
            yield _sse_frame("sessions_changed", {"sessions": get_cli_sessions()})
            while True:
                try:
                    payload = await _queue_get(subscriber)
                except queue.Empty:
                    yield b": keepalive\n\n"
                    continue
                if payload is None:
                    return
                yield _sse_frame(str(payload.get("type") or "sessions_changed"), payload)
        finally:
            watcher.unsubscribe(subscriber)

    return _sse_response(events())


@router.get("/api/approval/stream")
async def approval_events_sse(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[RealtimeService, Depends(get_realtime_service)],
    session_id: str = Query(min_length=1, max_length=256),
):
    await asyncio.to_thread(service._session_for_profile, session_id, identity.profile)
    from api.route_approvals import (
        _approval_sse_unsubscribe,
        approval_sse_subscribe_with_snapshot,
    )

    subscriber, initial = approval_sse_subscribe_with_snapshot(session_id)

    async def events():
        try:
            yield _sse_frame("initial", initial)
            while True:
                try:
                    payload = await _queue_get(subscriber)
                except queue.Empty:
                    yield b": keepalive\n\n"
                    continue
                if payload is None:
                    return
                yield _sse_frame("approval", payload)
        finally:
            _approval_sse_unsubscribe(session_id, subscriber)

    return _sse_response(events())


@router.get("/api/clarify/stream")
async def clarification_events_sse(
    identity: Annotated[RequestIdentity, Depends(require_identity)],
    service: Annotated[RealtimeService, Depends(get_realtime_service)],
    session_id: str = Query(min_length=1, max_length=256),
):
    await asyncio.to_thread(service._session_for_profile, session_id, identity.profile)
    from api.clarify import get_pending, sse_subscribe, sse_unsubscribe

    subscriber = sse_subscribe(session_id)
    pending = get_pending(session_id)
    initial = {"pending": pending, "pending_count": 1 if pending else 0}

    async def events():
        try:
            yield _sse_frame("initial", initial)
            while True:
                try:
                    payload = await _queue_get(subscriber)
                except queue.Empty:
                    yield b": keepalive\n\n"
                    continue
                if payload is None:
                    return
                yield _sse_frame("clarify", payload)
        finally:
            sse_unsubscribe(session_id, subscriber)

    return _sse_response(events())


@router.post("/api/terminal/start")
def start_terminal(
    request: TerminalStart,
    identity: Annotated[RequestIdentity, Depends(require_terminal_identity)],
    service: Annotated[RealtimeService, Depends(get_realtime_service)],
):
    return service.start_terminal(request, profile=identity.profile)


@router.post("/api/terminal/input")
def terminal_input(
    request: TerminalInput,
    identity: Annotated[RequestIdentity, Depends(require_terminal_identity)],
    service: Annotated[RealtimeService, Depends(get_realtime_service)],
):
    return service.terminal_input(request, profile=identity.profile)


@router.post("/api/terminal/resize")
def terminal_resize(
    request: TerminalResize,
    identity: Annotated[RequestIdentity, Depends(require_terminal_identity)],
    service: Annotated[RealtimeService, Depends(get_realtime_service)],
):
    return service.resize_terminal(request, profile=identity.profile)


@router.post("/api/terminal/close")
def close_terminal(
    request: TerminalClose,
    identity: Annotated[RequestIdentity, Depends(require_terminal_identity)],
    service: Annotated[RealtimeService, Depends(get_realtime_service)],
):
    return service.close_terminal(request, profile=identity.profile)


@router.get("/api/terminal/output")
async def terminal_output_sse(
    identity: Annotated[RequestIdentity, Depends(require_terminal_identity)],
    service: Annotated[RealtimeService, Depends(get_realtime_service)],
    session_id: str = Query(min_length=1, max_length=256),
):
    terminal = await asyncio.to_thread(
        service.terminal_queue,
        session_id,
        profile=identity.profile,
    )

    async def events():
        while True:
            try:
                event, data = await _queue_get(terminal.output)
            except queue.Empty:
                if terminal.closed.is_set() and terminal.output.empty():
                    yield _sse_frame("terminal_closed", {"exit_code": terminal.proc.poll()})
                    return
                yield b": terminal heartbeat\n\n"
                continue
            yield _sse_frame(str(event), data)
            if event in {"terminal_closed", "terminal_error"}:
                return

    return _sse_response(events())


@router.websocket("/api/terminal/stream")
async def terminal_stream(websocket: WebSocket):
    identity = await _accept_websocket(websocket)
    if identity is None:
        return
    if not connection_is_local_or_authenticated(websocket, identity):
        await _send_error_and_close(websocket, CoreApiError(403, "Terminal access is not allowed"))
        return
    service: RealtimeService = websocket.app.state.realtime_service
    session_id = str(websocket.query_params.get("session_id") or "").strip()
    if not session_id:
        await _send_error_and_close(websocket, CoreApiError(400, "session_id is required"))
        return
    try:
        terminal = await asyncio.to_thread(
            service.terminal_queue,
            session_id,
            profile=identity.profile,
        )
        while True:
            try:
                event, data = await _queue_get(terminal.output)
            except queue.Empty:
                if terminal.closed.is_set() and terminal.output.empty():
                    await websocket.send_json(
                        _event_envelope(
                            "terminal_closed",
                            {"exit_code": terminal.proc.poll()},
                            session_id=session_id,
                        )
                    )
                    break
                await websocket.send_json(
                    _event_envelope("heartbeat", {"status": "connected"}, session_id=session_id)
                )
                continue
            await websocket.send_json(_event_envelope(str(event), data, session_id=session_id))
            if event in {"terminal_closed", "terminal_error"}:
                break
    except CoreApiError as exc:
        await _send_error_and_close(websocket, exc)
    except (WebSocketDisconnect, RuntimeError):
        pass
