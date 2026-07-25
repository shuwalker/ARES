# ARES WebUI Architecture

Read [`../FOUNDATION.md`](../FOUNDATION.md) first. It is authoritative for
product ownership, vocabulary, runtime neutrality, and the animated activity
renderer.

## Runtime structure

ARES WebUI consists of two independently owned layers:

```text
React application (`frontend/`)
  -> normalized TypeScript contracts and adapters (`frontend/src/shared/`)
  -> same-origin HTTP and WebSockets (`/api/*`)
  -> Python controller (`fastapi_app/`, `api/`)
  -> profile-selected connection adapter (`fastapi_app/adapters/`)
  -> runtime, provider, and tool integrations
```

The React application owns navigation, interaction state, Local Profile
presentation, capability status, conversations, workspaces, terminal UI,
public shares, and future registered work views. It must boot when no assistant
runtime is connected.

The Python controller owns authentication, CSRF validation, persistence,
sessions, streaming, terminal processes, workspace access, provider discovery,
onboarding writes, integrations, and security boundaries.

## HTTP backend

`webui/fastapi_app/` is the production FastAPI application and Uvicorn is the
production server. `api/routes.py` and `server.py` are retained compatibility
modules while supported API families and regression contracts are progressively
assigned to modular routers and services; neither is a production dispatcher or
fallback path. The FastAPI application must not forward into the legacy request
handler merely to claim endpoint coverage.

The ported tranches cover the React client's health, Local Profile settings,
sessions, workspace reads, password login, public shares, chat controls and
streaming, selected-session activity, and embedded terminal controls and output. Each request family has
its own router and Pydantic wire models; shared service functions call existing
ARES domain modules directly. Ordinary cookie authentication, CSRF validation,
signed per-request profile selection, and same-origin WebSocket handshakes
apply to this tranche. Trusted-proxy, OIDC, and passkey session establishment,
advanced Settings/auth mutations, aggregate external-history reconciliation,
and API families not registered in `fastapi_app/routers/` remain compatibility
work until their dedicated modularization steps.

`fastapi_app/realtime.py` is a transport-neutral bridge, not a second runtime.
Chat execution remains owned by the existing run state, stream channels, and
durable run journal. WebSocket handlers subscribe before replay, replay journal
events after the browser cursor, discard duplicate event IDs, and consume
blocking thread-safe queues through `asyncio.to_thread()` so they do not block
Uvicorn's event loop. The exact contract and durability boundaries are recorded
in [`../../webui/docs/architecture/fastapi-websocket-transport.md`](../../webui/docs/architecture/fastapi-websocket-transport.md).

Framework selection is owned by `fastapi_app/adapters/`. A strict
`BaseLLMAdapter` contract covers health, model discovery, chat start, run
observation, status, and cancellation. The registry resolves Ares Agent,
JaegerAI, or Hybrid from the active Local Profile and the session override on
every request; the FastAPI services and routers contain no framework branches.
MCP implements the separate `BaseToolAdapter` contract because tools and model
execution are separate connection kinds. See
[`../../webui/docs/architecture/fastapi-adapter-registry.md`](../../webui/docs/architecture/fastapi-adapter-registry.md).

FastAPI feature routers are registered before the final React catch-all. An
unknown `/api/` path and a missing file-looking path return JSON 404 responses;
only non-file navigation paths receive the SPA shell. Each API family moves
only with contract tests for its response, authentication, profile context,
and failure behavior. Removing compatibility modules is a separate gate from
running the production server and requires parity for every retained contract.

## Frontend

- Source: `frontend/src/`
- Public files: `frontend/public/`
- Production output: `frontend/dist/`
- Development: Vite on `127.0.0.1:5173`
- Production serving: Python serves only `frontend/dist/`
- Optional development proxy: `ARES_VITE_DEV=1`

`src/shared/contracts.ts` defines ARES-owned frontend shapes. `ares-api.ts`
selects Python endpoints, `translators.ts` isolates backend wire formats,
`chat-stream.ts` normalizes WebSocket events, and `ares-context.tsx` owns shared
connection/session state. Components must not branch on inherited backend
formats when a translator can preserve the boundary.

The Connections view reads normalized records from `/api/connections`; it does
not infer runtime health from framework names. `/api/connections/{id}/models`
provides connection-scoped model discovery, while `/api/mcp/tools` remains a
read-only inventory of already-known tool state.

There is no `webui/static/` application and no legacy frontend fallback. A
missing build returns a clear 404 without swallowing `/api/` routes.

## Routing and security

All `/api/` routes are resolved before the SPA catch-all. File-looking requests
must resolve to a real file in `frontend/dist`; they are never rewritten to
HTML. Authenticated browser mutations include the request-scoped CSRF token
injected into the React shell. Public-share API reads and compiled public assets
are intentionally auth-exempt; they contain no private state by themselves.

The React `AuthGate` establishes password sessions through `/api/auth/*` before
rendering private application state. `/share/:token` is a public React route
backed by `/api/share/:token`.

## Failure behavior

- No model/runtime: application available, execution capability unavailable.
- Partial API failure: unaffected surfaces remain usable and status is limited.
- WebSocket interruption: reconnect with the last durable event ID, query run
  status after bounded retry failure, preserve the session, and report the
  transport condition without crashing the page.
- Missing production build: frontend navigation returns 404; APIs remain routed.
- Missing Vite server in development proxy mode: use the production React build.

## Verification

```bash
cd webui/frontend
npm ci
npm run typecheck
npm test
npm run build

cd ..
.venv/bin/python -m pytest tests/
```
