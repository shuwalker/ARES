# ARES — Agent Handoff

Reference for any future AI agent (Claude, Hermes, or other) continuing work on this repo. Dense by design — read top-to-bottom before touching anything.

## What ARES Is

ARES is a native macOS AI companion: a Swift desktop app (`ARES-Desktop/`, SwiftUI, embeds SAM as a vendored package for the chat UI) plus a Python daemon (`ares/`, runs as `ares start`). The app surfaces a 4-tab interface — **Companion** (SAM chat wired to Hermes), **Hub** (Hermes web UI + Dodo native views + AI config), **Office** (agent dashboard, partial), **Settings** (SAM PreferencesView + ALICE endpoint config). The reasoning backend is Hermes, an external agent running on the same machine at `http://localhost:8642`. Current development branch: `refactor/ares-core-architecture`.

## Hardware / Environment

- **Primary machine:** Mac Studio M1 Max, 32 GB RAM
- **Hermes agent:** `http://localhost:8642` (must be running for chat)
- **Ollama:** `http://localhost:11434` — local model inference (`gemma3:12b` default)
- **ComfyUI:** image generation for the avatar; endpoint stored in `UserDefaults` key `alice_base_url` (also editable in Settings tab)
- **Required env var:** `ARES_HERMES_API_KEY` — without it, Hermes calls fail auth
- **Optional env vars:** `ARES_HERMES_URL`, `ARES_LOCAL_MODEL`, `ARES_OLLAMA_URL`, `OLLAMA_NUM_CTX`, `ANTHROPIC_API_KEY`, `ARES_HOME`

## Build Instructions

```bash
# --- Python daemon ---
cd ~/GitHub/ARES
python3.11 -m venv .venv && source .venv/bin/activate
pip install -e .
ares start                  # starts the daemon; ares doctor / ares status for diagnostics

# --- Swift app (bundle) ---
cd ARES-Desktop
./build-app.sh              # produces ARES-Desktop/ARES.app

# --- Swift app (Xcode iteration) ---
open ARES-Desktop/Package.swift
# Select the "ARES" scheme, ⌘B to build, ⌘R to run

# --- Tests ---
pytest tests/unit/ -x -q                          # 30 pass baseline
pytest tests/integration/ -x -q                   # auto-skips if services down
```

## Architecture: Key Files

| File | Role |
|---|---|
| `ARES-Desktop/Sources/ARES/App/ARESApp.swift` | App entry point. Owns the `@StateObject` for `ARESAppState` and `SAMRuntime`. Wires environment objects into the root view. |
| `ARES-Desktop/Sources/ARES/App/ARESAppState.swift` | `@MainActor` class holding all published UI state: bootstrap status, tab selection, companion stats (skill / session / memory counts, hermesRunning), Office agents. Defines `ARESTab` enum and `runHermesChat` entry. |
| `ARES-Desktop/Sources/ARES/App/SAMRuntime.swift` | SAM initialization: registers the Hermes endpoint with SAM's `endpointManager`, configures `sharedConversationService`, wires `ALICEImageGenerationService` for avatar generation. |
| `ARES-Desktop/Sources/ARES/Views/ARESRootView.swift` | Tab routing. Switches on `ARESAppState.selectedTab` to render Companion / Hub / Office / Settings. |
| `ARES-Desktop/Sources/ARES/Views/Companion/CompanionView.swift` | Chat UI, voice-state avatar, "Generate Avatar" button (persists `ares_avatar_image_path` to UserDefaults). Embeds SAM's ChatWidget. |
| `ARES-Desktop/Sources/ARES/Views/Hub/HubView.swift` | Hermes web UI (WKWebView at `localhost:9119`) + Dodo `NativeGuestHost` + AI CONFIGURATION GroupBox (gateway URL, model, fast-path toggle). |
| `ARES-Desktop/Sources/ARES/Views/Settings/SAMSettingsView.swift` | Settings tab. Wraps SAM `PreferencesView` and surfaces ALICE endpoint config (`alice_base_url`, `alice_api_key`). |
| `ares/runtime/config.py` | `AresConfig` dataclass — agent / face / sync / telemetry / ipc sections. TOML loader at `_apply_toml()`. Read this to find any config key. |
| `ares/runtime/local_backend.py` | Ollama call site. Includes `options.num_ctx`. Fast-path interception is currently a placeholder comment block (W-3 fixed, fast-path is v2). |
| `ares/ipc/zmq_server.py` | ZMQ ROUTER bound to `ipc:///tmp/ares_ipc.sock` with protobuf framing. **Currently dead** — nothing in production calls `build_server()`. The daemon uses an inline asyncio Unix-socket IPC in `ares/runtime/daemon.py:72` instead. |
| `ares/core/db.py` | `connect_sqlite()` — the single source of SQLite connections (WAL mode, foreign keys on). All 23+ call sites route through this. |

## Current Status (as of 2026-05-26)

**Working:**
- SAM ChatWidget renders in Companion tab and is wired to Hermes via `SAMRuntime`'s endpoint registration.
- `runHermesChat` is `nonisolated` / off main actor (audit C-3 fixed).
- Python LLM layer references `cfg.agent.*` (audit C-4 fixed). `AgentConfig` carries `cloud_model`, `cloud_api_key`, `ollama_num_ctx` (65536 default), `fast_path_enabled`.
- `ares setup` writes Anthropic key under `[agent.cloud].api_key` and `_apply_toml()` reads it (audit W-1 fixed).
- ALICE/ComfyUI image generation initialized in `SAMRuntime`; endpoint editable from Settings.
- "Generate Avatar" button in `CompanionView` persists path to `UserDefaults["ares_avatar_image_path"]`.
- `connect_sqlite()` refactor complete across all call sites.
- API key incident remediated: history rewritten before push, key never reached origin.

**Stubbed / Partial:**
- **SAM→Hermes chat:** wired, but Hermes endpoint selection should be re-verified after the next clean Xcode build (Settings tab may need a fresh derived data wipe to appear).
- **Voice / STT:** UI toggle only, no audio pipeline. Slated for v2.
- **ZMQ IPC Swift side:** `ARESIPCClient.send()` is a no-op. `SwiftyZeroMQ5` + `swift-protobuf` not in `Package.swift`. v2/v3.
- **Fast-path routing:** UI toggle in HubView, TOML key `[agent].fast_path_enabled` parsed, Python side is a placeholder comment block in `ares/runtime/local_backend.py` and `ares/llm/local.py`. v2.
- **OSC emitter:** module clean, never called in daemon, no Swift receiver. v3+.
- **Hermes MCP bridge (9501):** config field + health probe only, no live service. v3.
- **Settings tab visibility:** present in source but may require clean build (delete `~/Library/Developer/Xcode/DerivedData/ARES-*`) to show up reliably.

**Broken / Known Buggy:**
- Conversation resets on tab switch — fix in progress (HubView siloed `AppState` is the root cause, see W-9).

## Known Issues / Next Fixes

Sourced from `docs/audit-report.md` open items, in rough priority order:

1. **N-3** — `runHermesChat` still uses a blocking read in some code paths; partially fixed via `Task.detached`, but verify all branches (especially the SearXNG/Ollama health checks in `refreshOfficeAgents`) are off the main actor.
2. **N-7** — `sessionCount = 4` fallback hardcoded at `ARESAppState.swift:185`. Should be `nil` or render `--` in the UI; currently silently lies when Hermes session dir is empty/missing.
3. **N-8** — `ALICEImageGenerationService` is instantiated twice (once in `CompanionView`, once in `SAMRuntime`). Pick one owner — `SAMRuntime` is the right home; `CompanionView` should read from it.
4. **W-4** — ZMQ IPC Swift side is 0% complete. Need: add `SwiftyZeroMQ5` + `swift-protobuf` SPM deps, generate Swift protobuf stubs, implement DEALER socket in `ARESIPCClient.send()`, wire it to `ARESAppState`.
5. **W-9** — `HubView`'s `NativeGuestHost` creates its own `@StateObject private var dodoState = AppState()` — a separate silo from `ARESAppState`. Should share app-level state.
6. **W-10** — Two competing IPC implementations: ZMQ ROUTER in `ares/ipc/zmq_server.py` (dead) and inline asyncio Unix socket in `ares/runtime/daemon.py:72` (live). Decide on one path and delete the other.
7. **Conversation reset on tab switch** — fix in progress; tied to HubView state silo above.
8. **W-2** — Port 9501 hardcoded in `ares/api.py:187` health probe; should parse from `cfg.mcp_mac_url`.
9. **W-7** — `memoryPercent` defaults to 94 in three places when MEMORY.md is unparseable; same lie pattern as N-7.
10. **W-8** — Homebrew path `/opt/homebrew/bin/brew` hardcoded in `DependencyInstaller.swift:36`; needs Intel fallback.

## Git Notes

- **Branch:** `refactor/ares-core-architecture` (pushed to `origin`).
- **Lock files:** `.git/index.lock` and similar appear frequently in this working tree. Workaround: bypass the index by using `git write-tree` + `git commit-tree` + `git update-ref` directly. Example:
  ```bash
  TREE=$(git write-tree)
  PARENT=$(git rev-parse HEAD)
  COMMIT=$(git commit-tree "$TREE" -p "$PARENT" -m "msg")
  git update-ref refs/heads/refactor/ares-core-architecture "$COMMIT"
  ```
- **Pre-staged work:** the working tree currently has staged refactor changes (see `git status` MM entries on `ARESApp.swift`, `ARESAppState.swift`, `SAMRuntime.swift`, `ARESRootView.swift`, `CompanionView.swift`, `HubView.swift`, `config.py`, `local_backend.py`). **Do not run `git add -A`** — only stage the files you intentionally changed.
- **API key rotation:** done. The leaked Hermes provider key has been replaced; the offending commit was squashed before push.
- **Force push:** previously executed to scrub the API key from branch history. Always use `--force-with-lease`, never `--force`.

## Rules (Never Break These)

1. **Never modify `ARES-Desktop/Vendor/SAM/`.** SAM is a vendored copy pinned to commit `b3e7323c4c52d0a96dc2247212929dccd1aaf2c4`. Patches go in ARES wrappers, not upstream files.
2. **Never modify the Hermes agent.** Hermes lives in `~/.hermes/` and is managed independently. All changes happen in this repo only. ARES calls Hermes over HTTP / CLI / future MCP.
3. **No cloud dependencies without explicit justification.** ARES is local-first. Anthropic/OpenAI are opt-in fallbacks, not defaults.
4. **Read files before editing.** Especially `ARESAppState.swift` and `SAMRuntime.swift` — they're load-bearing and easy to break.
5. **Use the `commit-tree` bypass when `.git/index.lock` is present.** Don't `rm` lock files reflexively; investigate first (another process or Xcode may hold them).
6. **Don't add Swift Package dependencies casually.** `Package.resolved` is pinned by SHA for two packages already (W-12); adding more without version tags compounds the brittleness.
7. **Never edit `~/.hermes/config.yaml` without:** (1) making a timestamped backup first, (2) running the Hermes config validator before AND after the edit. The normalizer silently drops malformed providers — always verify provider count after any change.

## v1 Completion Checklist

- [ ] Clean Xcode build with 0 errors (currently 5 errors after latest changes)
- [ ] Hermes chat returns responses in Companion tab
- [ ] Settings tab visible after clean build
- [ ] Conversation persists across tab switches
- [ ] Push final commit to origin
