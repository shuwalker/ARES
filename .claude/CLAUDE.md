# CLAUDE.md — ARES Repository Rules for AI Agents

This file defines mandatory rules for AI agents working in the ARES repository.

## Licensing

- ARES is licensed under AGPL-3.0 with a commercial dual-license option. See `LICENSE` and `COMMERCIAL-LICENSE.md`.
- Upstream Hermes WebUI code in `webui/` preserves its MIT notice in `webui/LICENSE`.
- Do not remove upstream copyright or license notices.
- Do not introduce code with terms incompatible with AGPL distribution.
- Do not change the license model without explicit maintainer approval.

## What ARES Is

ARES = Autonomous Reasoning & Execution System.

ARES is a Mac-first presentation and integration layer for one user-facing AI
assistant experience. It is not a multi-agent company simulator, and it is not
a replacement for JROS or Hermes. It provides client applications, adapter
configuration, identity projection, permission handling, remote access, and
presence rendering over independent runtimes and capability providers.

- ARES composes runtimes, tools, perception inputs, memory providers, voice
  services, avatar renderers, and device integrations behind one consistent
  user-facing assistant interface.
- JROS is the primary embodied runtime candidate: agent loop, bridge/client
  protocol, characters, voice/STT/TTS, tools/skills, event bus, hardware
  abstraction, robotics, and local/cloud task routing.
- Hermes Agent is an independent agent runtime ARES can call on for coding,
  terminal work, skills, sessions, cron, model/provider routing, delegation,
  memory-backed automation, and operations.
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
- Character/avatar systems are presence renderers. They may render JROS
  characters through 2D/3D/VR sprite rigs, Live2D-style surfaces, desktop modes,
  or future robotic bodies, while behavior comes from the active runtime.

## Public repo privacy boundary

Public repo code/docs must not contain maintainer-specific runtime values: personal paths, real Tailscale IPs/hostnames/tailnet names, personal hardware requirements, `.hermes`, `.ares/config`, SOUL.md, auth files, tokens, API keys, cookies, or live profile assumptions.

Use placeholders, detected values, or user-selected paths. In source code, prefer environment variables/configuration over user-folder assumptions. For JROS integration specifically, use `ARES_JROS_DIR` for source-checkout features and `ARES_JAEGER_HOME` / `JAEGER_HOME` for installed runtime discovery; never assume `~/GitHub`, a maintainer username, or another developer-only clone layout.

## Repository structure

Keep the merged layout intentional:

- `Package.swift` — Swift package manifest for the native app targets.
- `ARES-Desktop/Sources/ARESCore/` — protocol contracts, shared models, utilities.
- `ARES-Desktop/Sources/ARES/` — native macOS app target (WKWebView shell over the web app).
- `ARES-Desktop/Tests/ARESTests/` — native app tests.
- `webui/` — the ARES web app (Python server + frontend, adapted from Hermes WebUI). This is the ONLY web app tree: server, api/, static/, tests/, scripts/, Docker packaging, and env templates all live here. Never recreate api/, static/, server.py, or tests/ at the repo root — a stale root-level duplicate of this tree was retired on 2026-07-12.
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
  - `App/ARESApp.swift` — WKWebView shell: launches `webui/server.py` (via `webui/.venv`), wraps the web app in a native window with menu bar. The native provider layer (gateway providers, SQLite memory, voice, perception) was removed in the WKWebView pivot; product features belong in `webui/`.

`ExecutionBackendRouter` (ARESCore) owns product-level backend planning by capability. Prefer configured providers first, native fallbacks second, and development dummies only where explicitly allowed.

## Code quality standards

- Write production-quality, tested code.
- No stubs or placeholder implementations for user-facing setup paths.
- Follow existing patterns in `webui/api/`, `webui/static/`, and `ARES-Desktop/Sources/`.
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
cd webui
./scripts/test.sh tests/test_onboarding_static.py tests/test_ares_onboarding_public_portability.py tests/test_ares_provider_sync.py tests/test_jros_backend_streaming.py
```

Before proposing any commit:

```bash
git diff --check
swift build
swift test
cd webui && ./scripts/test.sh tests/test_onboarding_static.py tests/test_ares_onboarding_public_portability.py tests/test_ares_provider_sync.py tests/test_jros_backend_streaming.py
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
| Hermes | Peer full agentic framework backend | configured URL/API key/env/template |
| JROS | Peer full agentic framework backend | user-selected path/socket/env/template |
| ARES-native services | Product-owned UI/automation features | bundled/detected/configured per user |
| Ollama/local models | Local model inference backend | detected localhost or configured URL |
| Cloud providers | Remote model/tool providers | configured provider credentials/templates |
| Workflow tools | Automation/tool providers | detected/configured per user |

ARES must degrade gracefully when optional services are absent.
