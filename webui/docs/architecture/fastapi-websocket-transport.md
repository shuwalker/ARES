# FastAPI WebSocket transport

Status: implemented for the production FastAPI application and React frontend.

## Scope

The React application uses same-origin WebSockets for three live surfaces:

| Surface | Endpoint | Durable replay |
| --- | --- | --- |
| Assistant response | `WS /api/chat/stream?stream_id=...&after_event_id=...` | Yes, from the run journal |
| Selected-session activity | `WS /api/sessions/{session_id}/stream` | No; it is a refresh signal |
| Embedded terminal | `WS /api/terminal/stream?session_id=...` | No; PTY output is ephemeral |

Chat start, status, cancellation, and terminal control remain ordinary JSON
HTTP mutations. This keeps commands independently testable while WebSockets
carry observations.

## State ownership

The WebSocket layer does not own model execution or create a second run
registry. The established ARES layers remain authoritative:

- session/transcript storage owns durable conversation state;
- `api.config.STREAMS` and `StreamChannel` own live run fan-out;
- the run journal owns ordered replay and terminal run evidence;
- `api.background_process.SessionChannel` owns best-effort activity signals;
- `api.terminal` owns PTY processes and terminal output queues.

`fastapi_app.realtime.RealtimeService` translates those layers into operations.
It resolves the profile/session-selected `BaseLLMAdapter` for chat start,
subscription, replay, status, and cancellation; neither it nor the WebSocket
router imports a named framework. Current framework adapters share this journal
and channel observation implementation, so selecting a connection cannot create
a parallel stream registry.
The router subscribes to a chat channel before reading the journal, replays
events after the supplied cursor, and discards repeated `event_id` values while
draining the live queue. A durable terminal journal event ends the connection
even if a live channel is still awaiting cleanup.

Thread-safe runtime queues are read with `asyncio.to_thread()`. The FastAPI
event loop therefore remains available for unrelated HTTP and WebSocket work;
the existing model worker retains responsibility for generation.

## Event envelope

Every server message has this versioned shape:

```json
{
  "schema_version": 1,
  "event": "token",
  "data": {"text": "Hello"},
  "event_id": "run-id:12",
  "seq": 12,
  "stream_id": "run-id",
  "session_id": "session-id",
  "terminal": false
}
```

`event_id` and `seq` are present for journaled chat events. Heartbeats,
session-activity signals, and terminal output may have neither. `stream_end`,
`error`, and `cancel` are terminal chat events. Clients must treat unknown event
names as forward-compatible observations rather than fatal protocol errors.

## Authentication and authorization

Browser handshakes must have an `Origin` whose authority matches `Host`.
Authentication uses the ordinary HttpOnly ARES session cookie. When
authentication is enabled, the shell's session-bound CSRF token is carried as
the `ares.csrf.<token>` WebSocket subprotocol; it is not placed in a URL or log.
The server selects only the public `ares-v1` subprotocol.

Every chat stream and activity subscription is authorized against its owning
session and selected profile. Terminal access also retains the local-network
gate when authentication is disabled. Deployments behind a forwarding proxy
must enable authentication (or the explicit onboarding-open operator override)
before exposing a shell; forwarded-address headers are not trusted by this
migration tranche.

## Reconnect and failure behavior

The React chat client records the last received `event_id`, retries interrupted
connections with bounded exponential delay, and sends that cursor on reconnect.
The journal is the source for missed durable events; the live queue is only the
current observation path. Duplicate event IDs must not produce duplicate text,
tool activity, or terminal outcomes.

After retry exhaustion the client queries chat status. An active run is left
running and the interface reports the transport interruption. An inactive or
terminal run is reconciled from the session transcript. A missing model/runtime
may reject chat start, but it must not prevent the application, Local Profile,
workspace, settings, or navigation surfaces from loading.

Selected-session activity reconnects independently and is used to attach to
server-started turns or trigger a session refresh. It is not durable execution
evidence. Terminal output is also non-replayable; a dropped terminal connection
reports an interruption and may be reattached while the PTY remains alive.

Compatibility SSE functions may remain while their retained contracts are
modularized. They do not own separate execution state and are not the React
application's active realtime transport.
