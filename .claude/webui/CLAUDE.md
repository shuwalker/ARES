# CLAUDE.md — Web UI Specific Rules

This file applies to all work inside the `webui/` directory.

Read [`../FOUNDATION.md`](../FOUNDATION.md) first for the canonical ARES product,
ownership, vocabulary, multi-agent, and animated-environment boundaries.

## Server Entry Point

- The main application is `webui/fastapi_app/main.py`, launched with Uvicorn.
- `webui/server.py` and `webui/api/routes.py` are compatibility modules, not
  templates for new work or production fallback paths.
- It must remain self-contained and runnable after `pip install -r requirements.txt`.

## Dependencies

- Keep `requirements.txt` minimal.
- Optional dependencies (edge-tts, psutil, etc.) must stay optional and clearly documented.
- Do not add heavy ML/model dependencies directly to the WebUI shell. Prefer adapter boundaries to full frameworks (Hermes/JROS) or explicit ARES-native services.

## Onboarding & Setup Flow

- Onboarding presentation belongs in `webui/frontend/src/`; persistence and
  validation belong behind `webui/api/onboarding.py` contracts.
- All onboarding changes must support public, portable installs. Runtime-specific paths, network values, and framework locations must be detected, configured through environment variables/settings, or user-selected.
- Never hardcode maintainer-specific paths or clone layouts in WebUI source. For JROS, use `ARES_JROS_DIR` for source-checkout features and `ARES_JAEGER_HOME` / `JAEGER_HOME` for installed runtime discovery. `~/GitHub/...`, maintainer usernames, private volumes, and real Tailscale IPs are not allowed in production code.
- New steps must be added thoughtfully and tested against a fresh clone scenario.
- Onboarding creates a Local Profile independently of framework availability.
  Framework/provider connections are optional setup stages. Never equate
  profile completion with execution readiness; report both states explicitly.

## API Development

- New HTTP/WebSocket routes go in focused `webui/fastapi_app/routers/` modules;
  reusable domain and persistence logic belongs in focused `webui/api/` modules.
- Every new endpoint must include proper owner-scope and authentication checks.
- Do not add new dispatch branches to `api/routes.py`.

## Frontend Rules

- Use the React components, TypeScript contracts, Tailwind theme variables, and
  shared adapters already present in `webui/frontend/src/`.
- Do not introduce a second frontend framework or a Vanilla JS application shell.
- Backend response differences must be translated under `frontend/src/shared/`.
- Public files belong in `frontend/public/`; production serves `frontend/dist/`.
- Use plain engineering vocabulary in code and architecture. Conversation,
  Workspace, System status, Connections, Tasks, Runs, and Schedules are
  preferred over metaphorical component names.
- Conventional views and the animated 2D activity environment must render the
  same normalized task/run/event state. Do not create an animation-only state
  store or fabricate activity.

## Testing

- React behavior belongs in colocated Vitest files; Python behavior belongs in
  `webui/tests/`.
- Onboarding changes must be verified against the public portability test (`test_ares_onboarding_public_portability.py`).

## Hot Reload

- Preserve and improve the behavior when `ARES_WEBUI_RELOAD=1` is set.
- Changes to Python files should trigger automatic restart within ~2 seconds.
- Frontend development uses Vite HMR; production behavior must be verified with
  `npm run build` and the Python server serving `frontend/dist/`.

## Framework, Provider & Model Handling

- Hermes and JROS are peer full agentic frameworks behind ARES. Do not describe Hermes as the real backend or JROS as merely the body/accessory.
- Backend mode (`hermes`, `jros`, `hybrid`, or future ARES-native modes) is runtime/framework selection. Model/provider selection is separate and must stay real-provider based; never add fake `model="jros"` or `model_provider="jros"`.
- ARES WebUI is the UX/product layer: natural human request → ARES maps intent to framework/provider/tool calls → UI presents the result.
- Hybrid is first-class. A turn may use Hermes, JROS, and ARES-native automation together when that best satisfies the user intent.
- Multi-agent/model comparison and synthesis are first-class capabilities.
  Preserve each contribution and its provenance; do not force agents into
  employee, company, or org-chart semantics.
- New provider integrations must follow the existing endpoint resolver/provider-sync pattern and remain portable.
- Before claiming a WebUI backend/provider change is done, run a changed-file scan for `/Users/`, `~/GitHub`, private volume names, real Tailscale IPs, and Matthew-specific strings. Explicit regression tests may contain forbidden examples; production code may not.

Do not modify anything outside `webui/` unless explicitly instructed.
