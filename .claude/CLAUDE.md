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

**ARES** is only the **application name** (Autonomous Reasoning & Execution
System as a product package). It is not a character and not who the user talks to.

**Companion** = everything that is **not a worker**: the personal SI experience
(identity, journal, context, routing, scoring, permissions, workspace).
**Workers** = Ollama, jros, Hermes, cloud models, MCP, devices — execution only.

Read [FOUNDATION.md](FOUNDATION.md) and [docs/product-vision.md](../docs/product-vision.md).

Summary:

- ARES app hosts the Companion (Mac primary, WebUI remote, FastAPI controller).
- Companion owns unified journal (source of truth) + technical control intelligence.
- Workers execute; no silent default worker at first run.
- Do not present “ARES” as the chat persona. UI speaks Companion / assistant name.
- No mandatory company/employment metaphor.

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

Two Swift layers under `ARES-Mac_os/Sources/`:

- **ARESCore**
  - `Contracts/` — protocol contracts for providers, tools, memory, voice, etc.
  - `Conversation/` — unified conversation/memory services (product data plane).
  - `MCP/` — native macOS tools exposed to runtimes.
  - `Services/` — configuration, secrets, controller HTTP client.
  - `Dummies/` — safe no-ops for development only.
- **ARES**
  - `ARESApp.swift` — app lifecycle, menus, boot splash.
  - `ARESProductShell.swift` — **primary native product shell** (sidebar destinations:
    Home, Chat, Today, Connections, Workspace, Activity, Settings). Native Home and
    Connections first; other routes may host the shared WebUI surface while migrating.
  - `WebUIServerManager.swift` — starts FastAPI (`fastapi_app.main:app`) for local use
    and for remote clients on LAN/Tailscale.
  - Full-window WebUI-only mode is not the product goal; WebUI is the **remote/light**
    client with the same API contracts.

`ExecutionBackendRouter` (ARESCore) owns product-level backend planning by capability.
Prefer configured providers first, native fallbacks second, dummies only when explicit.

See `docs/product-vision.md` for the locked product decisions.

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
