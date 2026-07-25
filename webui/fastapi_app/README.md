# FastAPI application

This package is the production HTTP and realtime application for ARES. Startup
scripts launch `uvicorn fastapi_app.main:app`; the application does not forward
requests into a compatibility dispatcher. The former `server.py` and
`api/routes.py` implementations have been removed.

The structure follows the useful parts of the local Open WebUI reference:

- an application factory and explicit router registration;
- feature routers registered before static/SPA handling;
- a final SPA fallback that cannot swallow API misses;
- an ASGI lifespan boundary that owns startup recovery and background services.

Core API ownership is modular:

- `routers/health.py`: `/health`, `/api/health`, `/api/health/agent`;
- `routers/auth.py`: password-auth status, login, and logout;
- `routers/shares.py`: public read-only session shares;
- `routers/settings.py`: Local Profile settings read and assistant-name update;
- `routers/session.py`: session list, session read, and session creation;
- `routers/workspaces.py`: workspace list and safe directory listing.

The realtime tranche adds:

- `POST /api/chat/start`, status, and cancellation controls;
- `WS /api/chat/stream` for replayable chat events;
- `WS /api/sessions/{session_id}/stream` for selected-session activity;
- terminal start/input/close controls and `WS /api/terminal/stream`.

The adapter tranche adds `adapters/`:

- `BaseLLMAdapter` for runtime health, model discovery, streaming chat start,
  observation, status, and cancellation;
- concrete Ares Agent, JaegerAI, and Hybrid adapters over the existing
  framework integrations;
- `BaseToolAdapter` and `McpToolAdapter`, keeping tool capability discovery
  separate from runtime selection;
- a request-time registry selected from Local Profile/session configuration;
- `/api/connections`, connection-scoped model discovery, and the FastAPI
  `/api/mcp/tools` inventory.

`realtime.py` deliberately reuses the existing stream registry, session
activity channels, terminal manager, and durable run journal. Blocking queue
reads run through `asyncio.to_thread()` in the router, so live subscriptions do
not block the Uvicorn event loop. It resolves all chat operations through the
adapter registry and contains no framework or legacy-route imports. The default
turn starter invokes `api/chat_runtime.py`, a handler-free transaction service;
blocking setup runs in `asyncio.to_thread()` and generation continues in the
existing runtime-owned worker and journal pipeline.

`services.py` calls the existing ARES domain and persistence modules directly.
`request_context.py` preserves ordinary cookie authentication, CSRF validation,
and signed profile selection for these routes. Pydantic models in `schemas.py`
strictly validate mutation bodies while retaining established extra metadata in
read responses.

Run the production application against an existing React production build:

```bash
cd webui
uvicorn fastapi_app.main:app --host 127.0.0.1 --port 8787
```

Uvicorn startup, shutdown, recovery, background-service ownership, TLS launcher
arguments, React SPA routing, authentication, Local Profile management, and all
ARES API families are owned by FastAPI routers and reusable `api/` services.
New HTTP contracts must be added to a feature router; do not recreate a central
dispatcher or a second static frontend.
