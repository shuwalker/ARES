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

ARES is the human-facing UX/product layer over full agentic frameworks. It provides coherent UI, natural-language interaction, guided automation, owner-aware defaults, task continuity, self-audit, voice/face/presence, and cross-session context.

- Hermes Agent is a full independent agentic framework ARES can use through an adapter: tools, skills, gateway, sessions, cron, memory backend support, model/provider routing, delegation, and automation.
- JROS is a full independent agentic framework ARES can use through an adapter: agent loop, tools/skills, bridge/client protocol, voice/STT/TTS, character surfaces, event bus, hardware abstraction, embodiment, and robotics.
- ARES-native services are product-owned UI/automation/services ARES builds directly when the experience should not depend on either framework.
- Hybrid is first-class: ARES may use Hermes for one part of a request, JROS for another, and ARES-native UI/automation for the rest.
- ARES owns the user-facing identity and experience above all backends.

## Public repo privacy boundary

Public repo code/docs must not contain maintainer-specific runtime values: personal paths, real Tailscale IPs/hostnames/tailnet names, personal hardware requirements, `.hermes`, `.ares/config`, SOUL.md, auth files, tokens, API keys, cookies, or live profile assumptions.

Use placeholders, detected values, or user-selected paths. In source code, prefer environment variables/configuration over user-folder assumptions. For JROS integration specifically, use `ARES_JROS_DIR` for source-checkout features and `ARES_JAEGER_HOME` / `JAEGER_HOME` for installed runtime discovery; never assume `~/GitHub`, a maintainer username, or another developer-only clone layout.

## Repository structure

Keep the merged layout intentional:

- `Package.swift` — Swift package manifest for the native app targets.
- `Sources/ARES/` — legacy/lightweight Swift app surface kept as `ARESLegacy`.
- `Sources/AresTaskCLI/` — task CLI.
- `ARES-Modules/` — local Swift package used by legacy/native support code.
- `ARES-Desktop/Sources/ARESCore/` — protocol contracts, shared models, utilities.
- `ARES-Desktop/Sources/ARES/` — primary native macOS app target.
- `ARES-Desktop/Tests/ARESTests/` — native app tests.
- `webui/` — Python web server and frontend adapted from Hermes WebUI.
- `windows-app/` and `src-tauri/` — Windows/Tauri wrapper surfaces.
- `tools/` — standalone utilities.
- `docs/` — public documentation and assets.

Do not create new top-level directories without explicit approval. Do not modify Hermes Agent source code under a user runtime directory; build ARES adapters/config/templates instead.

## Native app architecture

Two Swift layers under `ARES-Desktop/Sources/`:

- **ARESCore**
  - `Contracts/` — protocol contracts: GatewayProvider, ReasoningBrain, MemoryStore, VoiceEngine, Perceiver, WorldModel, Identity, Mimicry, EventBus, KanbanBoard, CronScheduler, ToolProvider, PersonaProvider, Embodiment, ResourceProvider.
  - `Dummies/` — safe no-op implementations for development/testing only.
  - `Models/`, `Services/`, `Utilities/` — shared types, discovery, hub readers, registry, and support code.
- **ARES**
  - `App/` — entry point, app state, runtime, app delegate.
  - `Providers/` — concrete implementations for Hermes, JROS, Ollama, Claude, OpenAI, storage, voice, perception, and local event bus.
  - `Services/` — wiring, companion chat, agent tool routing, terminal, storage, browser services.
  - `Views/` — Companion, Hub, Kanban, Terminal, Files, Settings, widgets, and related UI.

`ARES-Desktop/Sources/ARES/Services/WiringBuilder.swift` owns protocol-to-implementation wiring. `ExecutionBackendRouter` owns product-level backend planning by capability. Prefer configured providers first, native fallbacks second, and development dummies only where explicitly allowed.

## Code quality standards

- Write production-quality, tested code.
- No stubs or placeholder implementations for user-facing setup paths.
- Follow existing patterns in `webui/api/`, `webui/static/`, `Sources/ARES/`, and `ARES-Desktop/Sources/`.
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
