# ARES WebUI — Fork Change Log

Tracks every modification made over the upstream [hermes-webui](https://github.com/nesquena/hermes-webui) repo.
Each entry: date, what changed, which files, why, and rollback path.

---

## 2026-07-10 — JROS in-process fallback when no gateway is running

**What:** The JROS backend now resolves execution in two steps: gateway first (`ARES_JROS_GATEWAY_URL`), and when no gateway is reachable but `ARES_JROS_DIR` points at a local checkout, ARES boots JROS in-process and runs the turn directly.

**Why:** The local single-machine case should be flip-the-toggle simple — no extra program to start. The gateway remains the path for remote machines and for sharing an already-running JROS. The two failure modes that sank the old in-process-only bridge are now guarded: an already-running JROS (exclusive instance lock) produces a message telling the user to close it or run `jaeger gateway` instead, and a missing instance says to run `jaeger setup` — the interactive wizard is never launched inside the web server.

**Files changed:**
- `webui/api/jros_gateway_chat.py` — `local_jros_root()`, `_boot_jros()` (cached, guarded), `_run_local_jros_turn()`; the chat worker falls back on gateway connection failure; `reset_jros_boot()` also drops the local boot cache (releasing the instance lock).
- `webui/api/backend_selector.py` — availability = gateway health (mode "gateway") else local checkout (mode "local"); `backend_status()` gains `jros_mode`.
- `webui/static/panels.js` — JROS status line reflects the mode.
- `webui/tests/test_jros_backend_streaming.py` — fallback turn, lock/setup guard messages, gateway-wins precedence, local-mode availability.

**Rollback:** Remove the fallback block in the chat worker and the local-boot helpers; drop `jros_mode` from `backend_selector.py`/`panels.js`.

**Verification:** `pytest tests/test_jros_backend_streaming.py` — 13 passed.

---

## 2026-07-10 — JROS backend rebuilt as a Hermes-style HTTP gateway bridge

**What:** Replaced the in-process JROS bridge (`api/jros_bridge.py`) and the ZMQ presence sidecar (`scripts/jros_presence.py`) with `api/jros_gateway_chat.py`, an HTTP/SSE client for the new JROS gateway server (`jaeger gateway`, added to the JROS repo as `jaeger_os/interfaces/http_gateway.py`). Hid the Hybrid backend option in the UI (server still accepts the value).

**Why:** The in-process bridge booted JROS via `boot_for_tui()`, which takes JROS's exclusive instance lock — so with JROS already running on the machine, every ARES turn failed with "instance is locked". And a JROS on another machine was unreachable by design: the ZMQ sidecar only answered pings and never executed turns (plus `pyzmq` was never a declared dependency). Running JROS as its own gateway server — the same integration shape as the Hermes Gateway bridge in `api/gateway_chat.py` — fixes both: no lock conflict, and a remote JROS is just `ARES_JROS_GATEWAY_URL=http://<jros-host>:8643`.

**Files changed:**
- `webui/api/jros_gateway_chat.py` — **NEW**. Gateway chat worker (`run_jros_streaming`), health probe (`jros_gateway_health`), remote reboot (`reset_jros_boot` → `POST /v1/reset`). Env: `ARES_JROS_GATEWAY_URL`, `ARES_JROS_GATEWAY_KEY`; config: `jros_gateway_url`.
- `webui/api/jros_bridge.py`, `webui/scripts/jros_presence.py` — **REMOVED** (superseded; `ARES_JROS_BUS_ENDPOINT` no longer read).
- `webui/scripts/jros_gateway.py` — **NEW**. Standalone single-file gateway launcher for JROS checkouts that don't ship `jaeger gateway` yet (the upstream JROS change is pending); vendored copy of the submitted module, auto-delegates to the native one when present.
- `webui/api/backend_selector.py` — availability = live `GET /v1/health` from the gateway (5s TTL cache); ZMQ probe and `ARES_JROS_DIR` execution fallback removed.
- `webui/api/characters.py` — now owns the `ARES_JROS_DIR` repo-root helper (character browser only).
- `webui/api/routes.py` — worker/reset imports point at `api.jros_gateway_chat`.
- `webui/static/index.html`, `webui/static/panels.js` — Hybrid option hidden; JROS status strings describe the gateway.
- `webui/README.md`, `README.md` — JROS gateway setup section (placeholder hostnames).
- `webui/tests/test_jros_backend_streaming.py` — rewritten against a fake in-test JROS gateway (real HTTP round-trip).

**Rollback:** Restore `api/jros_bridge.py` + `scripts/jros_presence.py` from git history, revert the import sites in `routes.py`/`backend_selector.py`/`characters.py`, and unhide the Hybrid button in `index.html`.

**Verification:** `pytest tests/test_onboarding_static.py tests/test_ares_onboarding_public_portability.py tests/test_ares_provider_sync.py tests/test_jros_backend_streaming.py`.

---

## 2026-07-05 — Onboarding wizard, MCP bootstrap, provider sync, JROS bridge

**What:** Expanded the first-run onboarding wizard with agent-prompt, Tailscale/iPhone, connect-test, and MCP-placement steps. Added MCP bootstrap CLIs (`tools/mcp-bootstrap/`, `tools/safari-mcp-bootstrap/`), Hermes/JROS provider sync (`api/ares_provider_sync.py`, `/api/ares/provider/sync`), and a default-off JROS chat bridge (`api/jros_bridge.py`).

**Why:** New ARES installs need a portable, backend-neutral path for private-network mobile access and correct local-vs-remote MCP placement. JROS backend mode and cross-backend provider sync should work without hardcoded machine paths.

**Files changed:**
- `webui/static/onboarding.js`, `webui/static/index.html`, `webui/static/style.css`, `webui/static/i18n.js` — wizard steps, MCP guidance, provider sync hook after setup.
- `webui/api/routes.py` — `/api/ares/provider/sync` with local-network gate when auth is disabled.
- `webui/api/ares_provider_sync.py`, `webui/api/jros_bridge.py` — **NEW**. Provider metadata sync and JROS streaming bridge (`ARES_JROS_DIR`, `ARES_JROS_INSTANCE` overrides).
- `tools/mcp-bootstrap/`, `tools/safari-mcp-bootstrap/` — **NEW**. Catalog/plan/configure/verify helpers.
- `webui/tests/test_onboarding_static.py`, `test_ares_provider_sync.py`, `test_jros_backend_streaming.py`, `test_ares_onboarding_public_portability.py` — coverage.

**Rollback:** Revert onboarding.js step list and static assets; remove new API modules and MCP bootstrap tools; drop provider-sync route block from `routes.py`.

**Verification:** `pytest tests/test_onboarding_static.py tests/test_ares_provider_sync.py tests/test_jros_backend_streaming.py tests/test_ares_onboarding_public_portability.py` — 18 passed.

---

## 2026-07-02 — Character avatar browser + public showcase

**What:** Added the ARES Characters panel as a visual browser for JROS `character/v1` personas and updated public docs/website imagery to show the avatar tab.

**Why:** Persona selection is now a product surface, not just backend config. The website and README should show the character roster, avatar art, traits, lore, and active identity control.

**Files changed:**
- `api/characters.py` — **NEW**. Character YAML loader for full character details.
- `api/routes.py` — `/api/ares/characters` and `/api/ares/character?id=<id>` endpoints.
- `static/characters.js` / `static/characters.css` — character list, detail pane, traits, lore, active persona selection.
- `static/characters/` and `static/persona-cards/` — 14 checked-in avatar card assets.
- `docs/index.html`, `docs/assets/character-tab-showcase.png`, `README.md`, `webui/README.md` — public website and repo docs showcase.

**Rollback:** Revert commit(s) adding `api/characters.py`, `static/characters.*`, character image assets, and docs/site references. Existing backend selector/persona APIs can remain.

**Verification:** Python compile and JS syntax checks passed; `/api/ares/characters` returned 14 characters; docs asset exists at 1600×960.

---

## 2026-07-02 — Sidebar session count fix (is_cli_session field)

**What:** Changed `webui_session_count` and `cli_session_count` in routes.py to use `s.get("is_cli_session")` instead of `_is_cli_session_for_settings(s)`. The `_is_cli_session_for_settings()` function misclassifies Claude Code sessions (source=external_agent, is_cli_session=True) as non-CLI, inflating the WebUI count by ~200.

**Why:** The frontend's `_isCliSession()` (sessions.js line 1842) simply checks `session.is_cli_session === true`. The backend count should use the same logic so the sidebar label matches the rendered list. Two bugs inflated the count from ~17 to ~217:
1. `default_hidden` sessions (200 cron/subagent sessions) were counted but hidden from the rendered list (already fixed by prior partial edit that added the `default_hidden` filter).
2. `_is_cli_session_for_settings()` misclassified 200 Claude Code sessions as non-CLI (fixed by this change).

**Files:** `api/routes.py` (lines ~2300-2308, two count blocks only)

**Rollback:** Change `s.get("is_cli_session")` back to `_is_cli_session_for_settings(s)` in both count blocks.

**Verification:** webui=17, cli=202 (confirmed live via curl after hot-reload restart)

---

## 2026-07-01 — Hot-reload system (two-tier)

**What:** Automatic server restart on Python source changes + instant browser reload on static file changes.

**Why:** Matthew edits the WebUI from any session (WebUI, Discord, CLI). Without hot-reload, every code change required a manual server restart, killing the active WebUI session. With this, edits are live in ~2s with zero manual intervention.

**Files changed:**
- `api/hot_reload.py` — **NEW**. Watchdog-based file watcher. Two tiers:
  - `.py` changes → 0.8s debounce → `os._exit(0)` → launchd KeepAlive restarts in ~2s. SSE reconnect handles the blip.
  - `.css/.js/.html/.svg/.png/.ico/.webmanifest` changes → 0.3s debounce → broadcasts `hot_reload` SSE event to all connected browser sessions → frontend does `location.reload()`. Zero server downtime.
- `server.py` — lines 662-672. Starts the watcher when `ARES_WEBUI_RELOAD=1`.
- `static/messages.js` — lines ~6864-6875. Added `hot_reload` SSE event listener in `startSessionStream()` that calls `location.reload()` on static file changes.
- `requirements.txt` — added `watchdog>=6.0`.
- `~/.hermes/start-webui.sh` — line 23: `export ARES_WEBUI_RELOAD=1` (config, not source).
- `~/Library/LaunchAgents/com.ares.hermes-webui.plist` — `KeepAlive=true` so launchd restarts on `os._exit(0)`.

**Rollback:** Set `ARES_WEBUI_RELOAD=0` or remove from `start-webui.sh`. Delete `api/hot_reload.py`. Revert `server.py` lines 662-672.

**Verified:** Touched `api/config.py` → server auto-restarted, launchd brought it back in ~3.5s. Tailscale access confirmed via `http://100.x.y.z:8787`. Static reload SSE broadcast confirmed via log output.

---

## 2026-07-01 — Tailscale serve TLS cleanup

**What:** Cleared stale Tailscale serve config that was wrapping port 8787 in TLS.

**Why:** iPhone PWA connects via a Tailscale URL such as `http://100.x.y.z:8787/?source=pwa` (plain HTTP — custom TLS certs are difficult on iPhone). Stale `tailscale serve` config was intercepting 8787 and serving HTTPS, causing "Client sent an HTTP request to an HTTPS server" error on iPhone.

**Files changed:** None (config only). Ran `tailscale serve --https=8787 reset` to clear the stale config.

**Rollback:** Re-run `tailscale serve --https=8787` to re-enable TLS on 8787. But don't — iPhone PWA needs plain HTTP.

---

## 2026-06-XX — Branding: ARES identity

**What:** Rebranded the WebUI from "Hermes" to "ARES" — title, logos, favicons, PWA manifest.

**Why:** ARES is a separate product from Hermes. The WebUI is the user-facing surface for Ares. Users should see "ARES", not "Hermes".

**Files changed:**
- `static/index.html` — page title, meta tags, PWA manifest links
- `static/manifest.json` — PWA name, short name, icons
- `static/favicon.*` — ARES app icon (from `Sources/ARES/Resources/AppIcon.icns`)
- `static/apple-touch-icon.png` — ARES icon for iOS home screen
- `webui/README.md` — updated to reference ARES and upstream fork

**Rollback:** Revert to upstream hermes-webui branding files.

**License note:** MIT license — original copyright preserved, ARES copyright stacked on top. Never remove original copyright.

---

## 2026-06-XX — Backend selector (Hermes/JROS/Hybrid)

**What:** Phase 1+2 of backend selector — dropdown in composer footer to pick which backend (Hermes, JROS, Hybrid) processes the turn. API + streaming wiring + persona picker UI.

**Why:** ARES supports multiple backends. The user picks which one to use per-conversation or per-turn.

**Files changed:**
- `api/backend_selector.py` — **NEW**. Backend selection API.
- `api/persona.py` — **NEW**. Dual-schema support for JROS 0.6.2 character/v1 + legacy persona/v1.
- `static/messages.js` — composer footer UI for backend/persona selection.
- `static/panels.js` — settings panel for backend defaults.

**Rollback:** Revert composer footer UI, remove backend_selector.py and persona.py.

**Git commits:** `424042e4`, `036e5e72`, `414f98e8`

---

## 2026-06-XX — ARES launch script

**What:** Custom launch script for ARES WebUI with proper env vars and dashboard startup.

**Files changed:**
- `start_ares.sh` — **NEW**. ARES-specific start script (alternative to upstream `start.sh`).

**Rollback:** Use upstream `start.sh` instead.

---

## Upstream sync notes

- **Upstream repo:** `nesquena/hermes-webui` (master branch)
- **Fork point:** Commit `1d5d88b7` ("Clean baseline: ARES app + webui + tools")
- **Sync strategy:** Pull upstream master periodically. ARES-specific changes are isolated to new files (`api/hot_reload.py`, `api/backend_selector.py`, `api/persona.py`) and small patches in `server.py` and `static/messages.js`. Conflicts should be minimal.
- **No upstream PRs:** ARES-specific features stay in the ARES repo. If upstream wants them, they can pull from our public repo. See session `20260701_135854_26d21385` for the full reasoning.

---

## How to update this log

When making changes to the ARES WebUI fork:
1. Add a new entry at the top (below the header, above the most recent entry)
2. Include: date, what changed, why, files touched, rollback path, verification status
3. Keep entries concise — this is a developer log, not documentation
4. Log everything: features, fixes, config changes, branding, even one-liners
5. If a change is reverted, mark it as **REVERTED** with date and reason, don't delete the entry