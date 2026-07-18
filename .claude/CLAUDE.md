# CLAUDE.md — ARES Repository Rules for AI Agents

This file defines mandatory rules for AI agents working in the ARES repository.

Read [`FOUNDATION.md`](FOUNDATION.md) before changing architecture, onboarding,
runtime integration, native-app responsibilities, navigation, or product
vocabulary. It is the canonical product definition; this file supplies
repository and implementation rules.

## Licensing

- ARES is licensed under AGPL-3.0 with a commercial dual-license option. See `LICENSE` and `COMMERCIAL-LICENSE.md`.
- Upstream Hermes WebUI code in `webui/` preserves its MIT notice in `webui/LICENSE`.
- Do not remove upstream copyright or license notices.
- Do not introduce code with terms incompatible with AGPL distribution.
- Do not change the license model without explicit maintainer approval.

## What ARES Is

ARES = Autonomous Reasoning & Execution System.

ARES is a simplified macOS controller and framework-independent WebUI for
operating and communicating with a personal Synthetic Intelligence locally or
from authenticated remote devices. It is not a replacement runtime. It may
coordinate and visualize multiple agents, models, tools, and processes,
including comparison and synthesis. A mandatory company/employment metaphor is
not part of the platform data model.

- ARES composes runtimes, tools, perception inputs, memory providers, voice
  services, avatar renderers, and device integrations behind one consistent
  user-facing assistant interface.
- JaegerAI is a first-class framework connection for agent execution,
  characters, voice/STT/TTS, tools/skills, events, hardware abstraction,
  robotics, and local/cloud task routing. ARES never re-implements JaegerAI.
  The current default backend may remain `jros`, but a Local Profile can be
  saved without JaegerAI installed or running. The UI must not claim execution
  is available until a suitable connection is verified.
- Hermes Agent is an optional addition ARES can call on for coding, terminal
  work, skills, sessions, cron, model/provider routing, delegation,
  memory-backed automation, and operations. Not installed by default —
  `webui/scripts/install.sh` only installs it with `--with-hermes` or an
  explicit interactive opt-in. A missing Hermes must never block onboarding
  or degrade the Companion; it only adds capability when present.
- OpenAI/ChatGPT-compatible services are model, reasoning, tool, or macOS
  integration providers. They may supply capabilities, but they do not define
  the assistant identity by themselves.
- ARES-native services are only for the experience layer: app shell, menus,
  onboarding, permissions, notifications, presence events, UI state, remote
  access, and adapter configuration.
- Persona, memory, and tool-execution ownership follows the selected runtime.
  ARES may project, summarize, and present that identity, but must not silently
  fork a competing persona or memory store. If an ARES-native runtime is ever
  added, it must be explicit.
- Hybrid means explicit capability composition, not routing every request
  through every backend. Prefer a clear turn owner and compose extra
  capabilities only when the task or user asks for them.
- The product direction is Mac-first: a SwiftUI app with native menus and macOS
  integrations launches and wraps the Web UI. The same Web UI remains available
  over Tailscale/LAN for phones, tablets, and other devices until native apps
  exist for them.
- Character/avatar systems are presence renderers. They may render JaegerAI
  characters through 2D/3D/VR sprite rigs, Live2D-style surfaces, desktop modes,
  or future robotic bodies, while behavior comes from the active runtime.
- The animated 2D activity environment is a renderer over real normalized
  tasks, runs, agents, models, tools, and events. It may show multiple animated
  counterparts working in parallel. It must not invent work or maintain a
  separate execution database.

## Public repo privacy boundary

Public repo code/docs must not contain maintainer-specific runtime values: personal paths, real Tailscale IPs/hostnames/tailnet names, personal hardware requirements, `.hermes`, `.ares/config`, SOUL.md, auth files, tokens, API keys, cookies, or live profile assumptions.

Use placeholders, detected values, or user-selected paths. In source code, prefer environment variables/configuration over user-folder assumptions. For JaegerAI integration specifically, use `ARES_JROS_DIR` for source-checkout features and `ARES_JAEGER_HOME` / `JAEGER_HOME` for installed runtime discovery; never assume `~/GitHub`, a maintainer username, or another developer-only clone layout.

## Repository structure

Keep the merged layout intentional:

- `Package.swift` — Swift package manifest for the native app targets.
- `ARES-Desktop/Sources/ARESCore/` — protocol contracts, shared models, utilities.
- `ARES-Desktop/Sources/ARES/` — native macOS app target (WKWebView shell over the web app).
- `ARES-Desktop/Tests/ARESTests/` — native app tests.
- `webui/` — the ARES web app: Python controller/API plus the React/Vite application in `frontend/`. This is the only web app tree. Never recreate `api/`, `frontend/`, `server.py`, or `tests/` at the repo root.
- `src-tauri/` — Windows/Tauri wrapper surface.
- `tools/` — standalone utilities.
- `docs/` — public documentation and assets.

Thin wrappers at the repo root (`install.sh`, `start.sh`, `ctl.sh`) delegate into `webui/`; keep them as delegators, not implementations.

Do not create new top-level directories without explicit approval. Do not modify Hermes Agent source code under a user runtime directory; build ARES adapters/config/templates instead.

## Native app architecture

Two Swift layers under `ARES-Desktop/Sources/`:

- **ARESCore**
  - `Contracts/` — protocol contracts: GatewayProvider, ReasoningBrain, MemoryStore, VoiceEngine, Perceiver, WorldModel, Identity, Mimicry, EventBus, KanbanBoard, CronScheduler, ToolProvider, PersonaProvider, Embodiment, ResourceProvider.
  - `Dummies/` — safe no-op implementations for development/testing only.
  - `Models/`, `Services/`, `Utilities/` — shared types, discovery, hub readers, registry, and support code.
- **ARES**
  - `App/ARESApp.swift` — WKWebView shell: launches the WebUI through its bootstrap/Uvicorn entry point (via `webui/.venv`), wraps the web app in a native window with menu bar. The native provider layer (gateway providers, SQLite memory, voice, perception) was removed in the WKWebView pivot; product features belong in `webui/`.

`ExecutionBackendRouter` (ARESCore) owns product-level backend planning by capability. Prefer configured providers first, native fallbacks second, and development dummies only where explicitly allowed.

## Code quality standards

- Write production-quality, tested code.
- No stubs or placeholder implementations for user-facing setup paths.
- Follow existing patterns in `webui/api/`, `webui/frontend/src/`, and `ARES-Desktop/Sources/`.
- New WebUI API endpoints must include proper authentication/owner-scope checks.
- Preserve hot-reload behavior (`ARES_WEBUI_RELOAD=1`).
- System-category or approval-required native tools must go through the approval broker/consent path.
- Cloud-only dependencies need local or graceful fallback behavior.

## Build & test

```bash
# Native app / Swift package
swift build
swift test

# Focused WebUI tests
cd webui/frontend && npm run typecheck && npm test && npm run build
cd .. && .venv/bin/python -m pytest tests/test_react_frontend_serving.py tests/test_jros_backend_streaming.py
```

Before proposing any commit:

```bash
git diff --check
swift build
swift test
cd webui/frontend && npm run typecheck && npm test && npm run build
cd .. && .venv/bin/python -m pytest tests/test_react_frontend_serving.py tests/test_jros_backend_streaming.py
```

Also run a privacy leak scan on changed public files. Any maintainer-specific match outside an explicit regression-test forbidden-string list is a blocker.

## Git rules

- Prefer feature branches and PRs for normal development.
- Keep `main` releasable: do not merge red builds intentionally.
- Preserve removed-but-useful code in `attic/` before deleting it.
- Do not commit build outputs, `.app` bundles, venvs, local runtime databases, generated auth files, or secrets.

## External stack assumptions

External services must be optional/detected, not hardcoded:

| Service | Default role | Expected configuration style |
|---|---|---|
| JaegerAI | First-class agent/voice/embodiment framework connection; current default where configured | detected or installed through an explicit connection flow; path via `ARES_JAEGER_HOME`/`JAEGER_HOME` |
| Hermes | Optional addition backend | opt-in via `--with-hermes`; configured URL/API key/env/template |
| ARES-native services | Product-owned UI/automation features | bundled/detected/configured per user |
| Ollama/local models | Local model inference backend | detected localhost or configured URL |
| Cloud providers | Remote model/tool providers for the Companion's `external_model` (JaegerAI) or Hermes, synced via `api/ares_provider_sync.py` — never the key itself, only provider/model/env-var name | configured provider credentials/templates |
| Workflow tools | Automation/tool providers | detected/configured per user |

ARES must degrade honestly when services are absent. Local Profile setup may
complete without a framework, but conversation, task execution, voice,
embodiment, memory, or tools must be reported unavailable until a connection
offering the required capability is verified.
