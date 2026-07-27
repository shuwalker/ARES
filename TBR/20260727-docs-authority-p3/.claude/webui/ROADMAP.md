# ARES WebUI Roadmap

See [`../ROADMAP.md`](../ROADMAP.md) for product priorities and
[`ARCHITECTURE.md`](ARCHITECTURE.md) for the current React/Python boundary.

WebUI work should prioritize Local Profile onboarding, normalized capability
contracts, streaming recovery, workspace/terminal completeness, responsive
behavior, accessibility, and browser-level verification. Do not restore the
retired Vanilla JavaScript application or treat inherited agent-framework
features as frontend architecture.

FastAPI/Uvicorn is the production backend. Core routes, WebSocket transport,
ASGI lifecycle ownership, the native chat transaction service, and the
profile-aware connection adapter registry are implemented. Final deletion of
`server.py` and `api/routes.py` remains gated on modularizing every retained API
and regression contract; see
[`../../webui/docs/architecture/fastapi-adapter-registry.md`](../../webui/docs/architecture/fastapi-adapter-registry.md).
