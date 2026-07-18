# ARES Roadmap

The React frontend migration is complete. Current work should follow
[`FOUNDATION.md`](FOUNDATION.md) and strengthen the product rather than restore
the retired framework-specific UI.

## Shipped foundation

- React/TypeScript/Vite WebUI served by the Python controller.
- Framework-independent frontend contracts and translation adapters.
- Today, Conversation, Workspace, Terminal, Activity, Connections, and Local
  Profile routes.
- Production FastAPI health, Local Profile, session, workspace, connection,
  model, tool, chat, terminal, password-auth, and public-share routes.
- Replayable WebSocket chat, selected-session activity, and terminal transport
  with graceful runtime absence and bounded reconnection.
- Profile/session-selected execution adapters for Ares Agent, JaegerAI, and
  Hybrid, plus a separate MCP tool adapter. FastAPI routers use normalized
  contracts and do not branch on a named framework.
- React-only public assets, login support, public shares, and SPA routing.
- Native macOS controller and remotely accessible same-product WebUI direction.

## Current backend migration gate

The production launcher now runs Uvicorn/FastAPI, ASGI lifecycle ownership is
implemented, and chat start is owned by the framework-neutral
`api/chat_runtime.py` transaction service. The legacy HTTP server is no longer a
production or fallback path.

Phase 2's final source-removal gate is not yet satisfied. `api/routes.py` still
contains supported API families and compatibility functions that have not been
ported to modular FastAPI routers, and retained backend regression tests import
those functions directly. `server.py` also remains for legacy contract tests.
Do not delete either file until those API families have named owners, equivalent
authentication/authorization behavior, and passing parity tests. A successful
React build or FastAPI boot alone is not evidence that deletion is safe.

## Next product work

1. Complete the Local Profile onboarding flow with Quickstart and Advanced
   paths, live credential checks, and explicit reachability.
2. Expand normalized Task, Run, Schedule, Delegation, provenance, approval, and
   memory contracts without importing framework metaphors.
3. Build the animated 2D activity environment as a renderer over real execution
   records.
4. Improve conversation recovery, attachment, voice, workspace editing, and
   terminal ergonomics through the shared adapters.
5. Add browser-level React coverage for authenticated, disconnected, mobile,
   streaming, and public-share flows.
6. Package repeatable frontend builds into macOS, Windows, Docker, update, and
   release workflows.
