# Session SSE Contract v1

- **Status:** Implemented
- **Author:** @rodboev
- **Created:** 2026-07-04
- **Tracking:** #4812

Refs #4812

---

## Problem

ARES defines a stable, cross-client contract for observing the lifecycle
of an individual session over SSE. Five or more future consumers — WebUI
reconnect/multi-tab, Android wrapper, iOS/PWA wrapper, desktop/TWA wrapper, and
test/CLI observers — each need a resumable, dedupe-safe event stream. Without a
shared contract, every client invents its own cursor, heartbeat, and event-type
semantics, multiplying coordination cost as new producers are added.

The contract was designed before implementation and is now served by the
modular FastAPI realtime router.

## Goals

- Define the SSE envelope and event-type vocabulary for the per-session
  stream `GET /api/sessions/{session_id}/events`.
- Specify replay identity using the existing run-journal cursor model.
- Specify the snapshot fallback for stale or evicted cursors.
- Document the distinction from the existing global session-list stream.
- Record the implementation decisions used by browser and external clients.

## Non-goals

- This contract does **not** change the meaning of `GET /api/sessions/events`
  (the global session-list invalidation stream implemented by
  `session_list_events_sse()` in `fastapi_app/routers/realtime.py`).
- This RFC does **not** replace or modify existing streams: `/api/chat/stream`,
  `/api/approval/stream`, or `/api/clarify/stream`.
- This RFC does **not** introduce Android, iOS, or PWA client code.
- This RFC does **not** claim Android/iOS background reconnect behavior or
  production proxy delivery; those require owner-reaching proof in a later
  implementation PR.
- This RFC does **not** promise a new session-global sequence counter in Phase 1.

## Current source inventory

### Existing global session-list stream

`GET /api/sessions/events` is a **different endpoint** from the one this RFC
defines. It is routed by FastAPI and implemented by
`session_list_events_sse()` in `fastapi_app/routers/realtime.py`. It emits bare
`sessions_changed` events and keepalives for any change to the session list. It
is a global invalidation signal, not a per-session lifecycle stream. The
`GET /api/sessions/{session_id}/events` is per-session and path-distinct.

### Heartbeat

`_HEARTBEAT_SECONDS = 5.0` (defined in `fastapi_app/routers/realtime.py`) is the current
heartbeat interval for SSE streams. Phase 1 reuses this constant rather than
adding a separate configurable knob.

### Run-journal cursor and replay

Current replay identity is run/stream-scoped:

Symbols in this inventory were verified against WebUI `master` when this RFC
was written. Function, constant, and endpoint **names** are the stable anchors:
this RFC deliberately cites them by name (not by line number) so a source-layout
source-layout shift cannot invalidate the doc or its contract test.

- `_parse_run_journal_event_id()` and `read_session_run_events()` in
  `api/run_journal.py` validate and replay the opaque cursor supplied through
  `Last-Event-ID` or `after_event_id`.
- Run-journal persistence constructs event identity as `stream_id:seq`.
- `_sse_frame()` emits the SSE `id:` field, while
  `_session_activity_sse_response()` coordinates replay and live observation
  in `fastapi_app/routers/realtime.py`.
- `api/streaming.py` writes current live agent streams to
  `STREAMS[stream_id]`.
- `api/streaming.py` appends SSE events to the run journal and carries
  per-item `event_id` into the live queue.

The existing run journal represents `session_id`, `stream_id`, `seq`, and
`event_id`, but **not** a session-global monotonic sequence. Phase 1 must not
promise a session-global counter because current source does not provide one.

## Proposed endpoint

```
GET /api/sessions/{session_id}/events
```

This endpoint is **path-distinct** from `GET /api/sessions/events`. The
`{session_id}` path segment is required; the global endpoint has no such segment.

Response: `Content-Type: text/event-stream`. Authentication and session
visibility checks reuse existing mechanisms.

## Envelope

Each SSE event carries a JSON payload with this structure:

```json
{
  "schema_version": 1,
  "session_id": "<session_id>",
  "event_type": "<string>",
  "event_id": "<opaque cursor>",
  "stream_id": "<stream_id>",
  "seq": <integer>,
  "emitted_at": "<ISO-8601 UTC>",
  "payload": { ... },
  "meta": { ... }
}
```

- `schema_version`: integer, always `1` for Phase 1 events.
- `session_id`: the session this event belongs to.
- `event_type`: one of the event types listed in the taxonomy below.
- `event_id`: opaque client cursor (see Cursor and resume semantics).
- `stream_id`: the run journal stream this event came from, if applicable.
- `seq`: monotonic within a stream/run (see Cursor and resume semantics).
- `emitted_at`: server-side emission timestamp in ISO-8601 UTC.
- `payload`: event-type-specific data.
- `meta`: optional; reserved for tracing and debug metadata.

Server-generated events that do not originate in the run journal, currently
`heartbeat` and `session_snapshot`, need an explicit `event_id` / `stream_id` /
`seq` rule before implementation. This RFC records that as an implementation
gate rather than inventing values without source support.

## Event taxonomy (Phase 1 draft)

| event_type | Source | Description |
|---|---|---|
| `chat_delta` | run journal / live stream | Token or chunk from an assistant reply. |
| `tool_call` | run journal / live stream | Tool invocation record. |
| `tool_result` | run journal / live stream | Tool result record. |
| `approval_request` | run journal | Approval prompt sent to the user. |
| `clarify_request` | run journal | Clarification prompt sent to the user. |
| `run_started` | run journal | Run entered active state. |
| `run_finished` | run journal | Run reached a terminal state (complete, cancelled, error). |
| `session_snapshot` | server fallback | Current session projection; emitted when replay is unavailable. |
| `heartbeat` | server | Keepalive emitted on the `_HEARTBEAT_SECONDS` cadence. |

The event-type table is a draft. The final table must be confirmed during
maintainer review before implementation.

## Cursor and resume semantics

`Last-Event-ID` is the standard SSE reconnect header. Clients send the last
`event_id` value seen on reconnect; the server uses it to resume replay from that
position.

**`event_id` is opaque to clients.** Its current source-compatible form is
`stream_id:seq`, as persisted by `api/run_journal.py`.
Clients must treat it as an opaque string and must
not parse or construct cursor values.

**`seq` is monotonic within a stream/run.** It is not a session-global counter
and is not promised to increase monotonically across streams or runs. Phase 1
does not claim a pre-existing session-global sequence because current source does
not provide one.

**Clients dedupe by `event_id`.** If a reconnect causes overlap with already-seen
events, clients use `event_id` to detect and skip duplicates.

## Replay source

Phase 1 uses the **durable run journal** as the replay source for replayable
events. The live `STREAMS[stream_id]` queue (in `api/streaming.py`) is
not a reliable replay source because it holds only recent in-memory state.

The implementation replays through `read_session_run_events()` and falls back
to the snapshot mechanism when journal entries are unavailable for a cursor.

## Snapshot fallback

When the `Last-Event-ID` cursor is evicted, expired, unknown, or refers to a
stream that is no longer replayable, the server must:

1. Emit a `session_snapshot` event containing the current session projection.
2. Continue the live stream from the present without pretending that missed
   events were replayed.

`session_snapshot` is a recovery boundary, not proof of exact missed-event
replay. Clients receiving a snapshot must treat prior cursor state as invalid and
resync from the snapshot payload.

## Heartbeat

The endpoint reuses `_HEARTBEAT_SECONDS` (defined in the realtime router) for
heartbeat cadence. A new per-session configurable heartbeat knob is **not** added
in Phase 1. The implementation PR must follow whatever value the constant holds
at implementation time; it must not hard-code a separate interval.

## Security and privacy

- Reuse existing auth and session visibility checks. A client must not be able to
  subscribe to events for a session it does not own.
- Payloads must not include credentials, raw provider API keys, or unsanitized
  internal error details.
- `meta` fields are for tracing and debug metadata and must not carry
  security-sensitive values in production.

## Implementation decisions and follow-up validation

The FastAPI implementation uses stream-scoped sequence numbers, durable journal
replay, session snapshots after invalid cursors, and the same identity checks as
ordinary session reads. The following remain operational validation concerns:

1. **Sequence semantics**: Maintainer must confirm that stream/run-scoped `seq`
   (not session-global) is acceptable for Phase 1 clients.
2. **Retention policy**: How long are run journal entries retained for replay?
   What is the eviction boundary that triggers the snapshot fallback?
3. **Event-type table**: The taxonomy above is a draft. The complete event-type
   list must be confirmed during review of this RFC.
4. **Auth behavior on reconnect**: Does `Last-Event-ID` replay require the same
   auth token, or can it continue across token refresh?
5. **Client proof**: At least one browser-based client (WebUI) and at least one
   non-browser client (Android wrapper or CLI) must provide owner-reaching
   reconnect proof before implementation closes #4812.
6. **Proxy and keepalive**: The 5 s heartbeat choice must survive real proxy
   deployments. This requires manual-owner-proof or standards-doc evidence in the
   implementation PR.
7. **Server-generated event identity**: Maintainer must confirm how
   `heartbeat` and `session_snapshot` populate `event_id`, `stream_id`, and
   `seq`, because those events do not originate in the run journal.

## Bypass risks

Future implementation work must not:

- Introduce an in-memory-only cursor that bypasses the run journal.
- Conflate `GET /api/sessions/events` (global session-list invalidation) with
  `GET /api/sessions/{session_id}/events` (per-session lifecycle).
- Promise a session-global monotonic sequence without defining a migration from
  the current stream/run-scoped model.

Tests in `tests/test_issue4812_session_sse_contract_rfc.py` assert these
boundaries so review catches regressions against this contract.

## Rollout record

1. The contract vocabulary was recorded before implementation.
2. FastAPI added `GET /api/sessions/{session_id}/events` with durable replay.
3. The React client retains SSE compatibility while WebSocket chat uses the
   same event envelope and run journal.
4. Browser and non-browser reconnect proof remains part of release validation.
