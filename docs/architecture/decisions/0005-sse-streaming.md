# ADR-0005: Streaming uses Server-Sent Events

**Status:** Accepted (inherited)
**Date:** 2026-07-22 (recorded retroactively)

## Context

ARES inherited SSE streaming from the upstream WebUI, whose own ADR-004 chose SSE over
WebSockets. ARES never recorded the reasoning, so the choice has periodically
looked arbitrary.

Chat streaming is one-directional: the server pushes tokens, tool activity, and
completion events. The client's only upstream actions — send, cancel, approve —
are ordinary HTTP requests.

## Decision

Keep SSE. `POST /api/chat/start` returns a `stream_id`; the browser opens
`EventSource('/api/chat/stream?stream_id=…')` and consumes typed events until
`done` or `error`.

## Consequences

Good:

- Plain HTTP: works through the WKWebView shell, reverse proxies, and Tailscale
  without upgrade negotiation.
- Automatic reconnection semantics in the browser.
- Auth is the same cookie/identity path as every other endpoint — no separate
  handshake.
- Cancellation is an ordinary POST, not an in-band protocol message.

Costs:

- One connection per active stream; stream ownership needs explicit guards.
- No client→server channel on the same connection, so approvals and cancels are
  separate requests.

## Note

`fastapi_app/routers/realtime.py` also exposes a WebSocket route for session
streams. SSE remains the path used by the Chat surface; the WebSocket route is
not the default and should not be treated as a second parallel implementation
without a product decision.

## Revisit if

Streaming becomes genuinely bidirectional and latency-sensitive — for example
live voice, where round-trip audio would justify a persistent duplex channel.
