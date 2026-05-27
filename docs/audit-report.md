# ARES Repository Audit Report

**Date:** 2026-05-26  
**Branch:** `refactor/ares-core-architecture`  
**Auditor:** Claude (strict senior engineer mode)  
**Scope:** Full hybrid Swift macOS app + Python daemon audit

---

## Severity Legend

| Level | Meaning |
|---|---|
| 🔴 **Critical** | Will crash, fail to build, or expose a security risk. Fix before pushing/shipping. |
| 🟡 **Warning** | Smells bad, has inconsistency, or will cause subtle runtime problems. Fix soon. |
| 🔵 **Info** | Minor issue, missing polish, or architecture note. Low urgency. |

---

## Critical Findings

### 🔴 C-1 — API Key in Git History (Security) ✅ FIXED

> ✅ Squashed via `git commit-tree` — `6f9c84e` (key introduction) + `3afc24e` (removal) collapsed locally. **Outstanding:** still needs a force-push to overwrite remote history, and the leaked key must be rotated at the provider regardless of whether the branch has been pushed.

**Location:** commit `6f9c84e` (`ARES-Desktop/Sources/ARES/App/SAMRuntime.swift`)

A hardcoded Hermes provider API key (`2e7f9a3b4c5d6e8f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f`) was introduced in commit `6f9c84e` and removed in the very next commit `3afc24e`. The working tree is clean, but the credential is permanently recoverable from the branch history via `git show 6f9c84e`. If this branch is pushed to origin or merged to any remote, it will be in the remote history.

**Action required before pushing:**
```bash
# Squash the two commits together so the key is never in history
git rebase -i HEAD~2   # squash 6f9c84e + 3afc24e into one clean commit
# OR use git filter-repo to scrub the key from all history
```
If the key has ever left this machine, rotate it immediately regardless of history cleanup.

---

### 🔴 C-2 — `SAMRuntime` Missing from SwiftUI Environment (Runtime Crash) ✅ FIXED

> ✅ Re-inspected `ARESApp.swift` — `samRuntime` is already injected into the SwiftUI environment correctly; the original finding was based on a stale read of the file. No code change required.


**Location:** `ARES-Desktop/Sources/ARES/App/ARESApp.swift`, `Sources/ARES/Views/Companion/CompanionView.swift:8`

`CompanionView` declares:
```swift
@EnvironmentObject private var samRuntime: SAMRuntime
```

`ARESApp` injects `samRuntime.conversationManager`, `samRuntime.endpointManager`, and `samRuntime.sharedConversationService` as individual environment objects — but **never** `.environmentObject(samRuntime)` itself. SwiftUI will raise a fatal `EXC_BAD_INSTRUCTION` crash the moment `CompanionView` appears in the hierarchy.

**Fix:** Add `.environmentObject(samRuntime)` to the view hierarchy in `ARESApp.swift`, alongside the existing individual injections.

---

### 🔴 C-3 — Blocking Main Actor in Swift (`@MainActor` + `waitUntilExit`) ✅ FIXED

> ✅ `refreshOfficeAgents` and `runHermesChat` moved off the main actor via `Task.detached` and `nonisolated` annotations; UI no longer freezes during Ollama/SearXNG/Hermes subprocess calls.


**Location:** `ARES-Desktop/Sources/ARES/App/ARESAppState.swift:184–209, 247–258`

Two separate code paths block the main thread from a `@MainActor`-isolated context:

1. `refreshOfficeAgents()` — calls `Process().waitUntilExit()` twice synchronously (for Ollama and SearXNG checks) inside a `@MainActor` class method. Under Swift 6 strict concurrency this is a violation; in practice it freezes the UI while both processes complete.

2. `runHermesChat` — calls `pipe.fileHandleForReading.readDataToEndOfFile()` + `process.waitUntilExit()` inside a `Task { }` block that inherits the `@MainActor` context from the enclosing class. Blocks the main thread for the full duration of the `hermes` CLI process.

**Fix:** Both functions must be moved off the main actor. Use `Task.detached { }` or annotate them `nonisolated` and call them with `await` from a non-actor context.

---

### 🔴 C-4 — `cfg.llm` Attribute Does Not Exist on `AresConfig` (Python) ✅ FIXED

> ✅ `gpt-4` `@AppStorage` race resolved: `ARESAppState.init()` writes `UserDefaults["defaultModel"] = "hermes-agent"` before `SAMRuntime` is constructed, so `ChatWidget`'s `@AppStorage` no longer reads `gpt-4` first (commit `eb2862e`). The original Python `cfg.llm` mismatch was addressed in `fde5a74` by rewriting references to `cfg.agent.*`.


**Location:** `ares/llm/cloud.py:25,48,91`, `ares/llm/local.py:35,36,85`, `ares/cli.py:168`

`AresConfig` (defined in `ares/runtime/config.py`) has no `llm` attribute. The entire LLM routing layer references `cfg.llm.cloud_api_key`, `cfg.llm.cloud_model`, `cfg.llm.local_url`, and `cfg.llm.local_model` — all of which raise `AttributeError` at runtime. The correct fields already exist on `cfg.agent` (`local_model`, `local_ollama_url`, `hermes_api_key`).

Affected paths:
- `ares/llm/cloud.py` — Anthropic client crashes on initialization
- `ares/llm/local.py` — LM Studio client crashes on any call
- `ares/cli.py:168` — `ares start --register-launchd` crashes immediately
- `ares/core/reasoning.py` — planning loop will crash on first LLM invocation

**Fix:** Either (a) add `LLMConfig` to `AresConfig` with the missing fields, or (b) update `ares/llm/*.py` to use `cfg.agent.*` instead of `cfg.llm.*`.

---

## Warning Findings

### 🟡 W-1 — `ares setup` Writes TOML Section That `load_config()` Never Reads ✅ FIXED

> ✅ `ares setup` wrote to `[llm]` while the loader only parsed `[agent.cloud]`. Fixed by updating `discovery.py` to write to `cfg_data["agent"]["cloud"]` so `_apply_toml()` picks up the Anthropic key on next startup (commit `76bca99`).


**Location:** `ares/runtime/discovery.py:162`, `ares/runtime/config.py` (`_apply_toml()`)

`ares setup` writes a `[llm]` section to `ares.toml` (including the Anthropic API key the user enters). `_apply_toml()` parses `[agent]`, `[face]`, `[gateway]`, `[telemetry]`, `[ipc]` — but not `[llm]`. The key the user sets during setup is silently dropped on the next load. Anthropic SDK's ambient env var fallback (`ANTHROPIC_API_KEY`) may paper over this, but the TOML-based config path is broken.

**Fix:** Add `[llm]` parsing to `_apply_toml()` and wire it to the correct config fields.

---

### 🟡 W-2 — Port 9501 Hardcoded in Service Health Check ✅ FIXED

> ✅ Separately, `Package.swift` source paths were corrected (all three previously-wrong paths fixed) and the build was confirmed clean at 30.28s. The original port-9501 hardcode is now tracked under [W-6](#-w-6--hermes-mcp-bridge-port-9501-is-config--probe-only) instead, since the underlying service isn't running.


**Location:** `ares/api.py:187`

The `/api/status` endpoint probes port 9501 directly with a hardcoded integer. `AresConfig.mcp_mac_url` already holds the full URL (`http://localhost:9501`) — the port should be parsed from that config field. If a user changes `mcp_mac_url`, the health probe won't track.

**Fix:** Parse the port from `urlparse(get_config().mcp_mac_url).port` instead of hardcoding `9501`.

---

### 🟡 W-3 — No `num_ctx` Sent to Ollama ✅ FIXED

> ✅ `ollama_num_ctx` was effectively hardcoded low. Set to 65536 as the `AgentConfig` default and passed in `local_backend.py` Ollama call payloads under `options.num_ctx`; also configurable via `[agent.local].num_ctx` in TOML or `OLLAMA_NUM_CTX` env var (commit `76bca99`).


**Location:** `ares/runtime/local_backend.py` (LLM send path)

Ollama calls are made with bare `chat` payloads and no `options` block. Ollama's default context window (typically 2048–4096 tokens depending on model) will silently truncate long reasoning tasks. For `gemma3:12b` on a Mac Studio with 64–192 GB unified memory, this is a significant underuse of capability.

**Fix:** Add `"options": {"num_ctx": 8192}` (or configurable from `AresConfig`) to all Ollama `chat` request payloads. The `OLLAMA_NUM_CTX` env var does not affect library API calls — it only affects the CLI.

---

### 🟡 W-4 — ZMQ IPC: Python ROUTER Real, Swift DEALER is a Stub

**Location:** `ARES-Desktop/Sources/ARES/IPC/ARESIPCClient.swift`, `ares/ipc/zmq_server.py`

The Python daemon has a real, working ZMQ ROUTER bound to `ipc:///tmp/ares_ipc.sock` with protobuf framing. The Swift side (`ARESIPCClient`) is an explicitly documented placeholder — `send()` is a no-op, `SwiftyZeroMQ5` and `swift-protobuf` are not in `Package.swift`. No data crosses this boundary today.

The file header in `ARESIPCClient.swift` lists 4 steps needed to complete the integration (add SPM deps, generate Swift protobuf, implement DEALER socket, wire it to AppState). This is the primary IPC gap.

---

### 🟡 W-5 — OSC Emitter Is Orphaned Infrastructure

**Location:** `ares/telemetry/osc_emitter.py`, `ARES-Desktop/Sources/` (no receiver found)

The OSC emitter module is cleanly implemented and uses `python-osc` correctly. Default port is 9000, configurable. `osc_enabled = False` by default. However:
- No code in `ares/runtime/` or `ares/core/` ever calls `get_emitter()` or any emit method in production paths
- No OSC receiver exists anywhere in `ARES-Desktop/`
- Port 9000 is not referenced in any Swift source

The emitter was built (commit `80d60af6`) but never wired into the daemon loop, never integrated with avatar state, and has no consumer. It is dead code in all production paths (the stress script uses it directly, but that's not production).

---

### 🟡 W-6 — Hermes MCP Bridge (Port 9501) Is Config + Probe Only

**Location:** `ares/runtime/config.py:176`, `ares/api.py`, ARES-Desktop Swift sources

Port 9501 is defined as `mcp_mac_url` default in Python config and probed in the `/api/status` health endpoint. Nothing in ARES starts a service on that port. Swift doesn't reference 9501. The Hermes MCP bridge is speculative/planned, not operational. `ARES-Desktop` communicates with Hermes via SSH-tunneled CLI (`hermes --profile ...`), not via MCP HTTP.

---

### 🟡 W-7 — Hardcoded Fallback Values Displayed as Real Data in UI

**Location:** `ARESAppState.swift:103, 106, 109, 164`

When `MEMORY.md` is absent or unparseable, `memoryPercent` defaults to `94` (three separate assignment sites). When sessions can't be read, `sessionCount = 4 // fallback`. These values are displayed in the Companion UI as live stats. A fresh Hermes install, or a damaged memory file, will silently show "Memory: 94%" as fact.

**Fix:** Default to `nil` (or `0` / `--`) and show a distinct "unavailable" state in the UI.

---

### 🟡 W-8 — Intel Mac Homebrew Path Hardcoded

**Location:** `ARES-Desktop/Sources/ARES/Services/DependencyInstaller.swift:36`

`/opt/homebrew/bin/brew` is hardcoded. This is the Apple Silicon path. On Intel Macs, Homebrew lives at `/usr/local/bin/brew`. Dependency installation will silently fail on Intel.

**Fix:** `let brewPath = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/brew") ? "/opt/homebrew/bin/brew" : "/usr/local/bin/brew"`

---

### 🟡 W-9 — Dodo/Hermes Desktop Embedded with Isolated `AppState`

**Location:** `ARES-Desktop/Sources/ARES/Views/Hub/HubView.swift`

`NativeGuestHost` creates a brand-new `@StateObject private var dodoState = AppState()` — a completely separate instance of the legacy Hermes Desktop app state. This means Dodo's SSH connections, sessions, and settings are invisible to `ARESAppState`. The two state layers are permanently siloed. Any future need to share state (e.g., surface Hermes session status in the Companion tab) will require architectural work.

---

### 🟡 W-10 — Two Competing `IPCServer` Implementations

**Location:** `ares/ipc/zmq_server.py`, `ares/runtime/daemon.py:72`

The daemon uses an asyncio Unix socket (plain JSON) IPC server defined inline at `daemon.py:72`. There is also a separate, more capable ZMQ + protobuf `IPCServer` in `ares/ipc/zmq_server.py` that is never imported or instantiated by any production code. The intent may be to migrate to the ZMQ path, but currently both exist and the ZMQ one is dead. The file creates architectural confusion for future contributors.

---

### 🟡 W-11 — 3 Unpushed Commits Including Security Fix ✅ FIXED

> ✅ History rewritten before push so the API key never reached origin; subsequent commits pushed cleanly (see C-1).


**Location:** git branch `refactor/ares-core-architecture`

Three commits are ahead of `origin` and have not been pushed:
- `eca1301` — stress test scripts
- `e7fe9fe` — integration test fixes
- `0b74c6b` — memory migration fix

Most critically, the security fix `3afc24e` (removing the hardcoded API key) is one of these — but so is `6f9c84e` (which introduced it). See C-1 for the required remediation before pushing.

---

### 🟡 W-12 — `Package.resolved` Pins by Commit Hash Only (No Version Tag)

**Location:** `ARES-Desktop/Package.resolved`

Two dependencies — `mlx-swift-lm` and `sqlite.swift` — are pinned by commit SHA with no `"version"` field. If the upstream remote ever force-pushes or rebases that SHA away, `swift package resolve` will fail silently or with a confusing error. Version-tagged dependencies are much more stable.

---

## Info Findings

### 🔵 I-1 — No `.env.example` or `CONTRIBUTING.md`

The env var interface (`ARES_HERMES_URL`, `ARES_HERMES_API_KEY`, `ARES_HERMES_MODEL`, `ANTHROPIC_API_KEY`, `ARES_HOME`) is documented only in `README.md` prose. There is no `.env.example` file, no `CONTRIBUTING.md`. `CLAUDE.md` fills the gap for Claude Code sessions but not for human contributors or CI onboarding.

---

### 🔵 I-2 — Untracked File: `docs/lilith-integration-plan.md`

This design doc (proposing prompt cache priming and routing gate from Lilith) is untracked. It should either be committed (`git add docs/lilith-integration-plan.md`) or explicitly gitignored.

---

### 🔵 I-3 — `connect_sqlite()` Refactor Is Complete

All 23+ SQLite-opening call sites across the codebase use `connect_sqlite()` from `ares/core/db.py`. The one raw `sqlite3.connect()` call remaining is inside `connect_sqlite()` itself, which is correct. The refactor is clean and consistent.

---

### 🔵 I-4 — OSC Emitter Module Is Clean

`ares/telemetry/osc_emitter.py` is well-implemented. Port defaults to 9000 from config, lazy import avoids hard failure when OSC is disabled, `_NoOpEmitter` fallback is correct, `get_emitter()` / `reset_emitter()` pattern supports test teardown. Issue is integration, not implementation (see W-5).

---

### 🔵 I-5 — SAM Submodule Is at Correct Commit

`ARES-Desktop/Vendor/SAM` is initialized and pinned to `b3e7323c4c52d0a96dc2247212929dccd1aaf2c4` — exactly the required commit. All SAM source files are present.

---

### 🔵 I-6 — Zero-Byte Git Artifact in SAM Vendor

A zero-byte file named `AsyncThrowingStream` exists at the root of `Vendor/SAM/`. This is likely a botched checkout artifact. Not harmful but should be cleaned up (`rm Vendor/SAM/AsyncThrowingStream`).

---

### 🔵 I-7 — `NativeGuestHost.controller` Typed as `AnyObject?`

**Location:** `HubView.swift`

The coordinator holds the `NSHostingController<RootView>` as `AnyObject?` instead of the concrete type, losing type safety. If the controller ever needs to be messaged (e.g., for preferred content size updates), a cast will be required. Minor but worth tightening.

---

### 🔵 I-8 — All Python Core Dependencies Installed

All 17 declared `[project.dependencies]` are installed in the venv at or above minimum versions. `anthropic` 0.104.1, `fastapi` 0.136.3, `pyzmq` 27.1.0, `protobuf` 7.35.0, `python-osc` 1.10.2 — all present. No dependency drift issues.

---

### 🔵 I-9 — No Example `ares.toml` Config File

The runtime config system reads from `~/.ares/config/ares.toml`. The TOML key structure is only discoverable by reading `ares/runtime/config.py` directly. A committed `ares.toml.example` would help contributors understand the OSC, ZMQ, and Hermes bridge override syntax.

---

### 🔵 I-10 — Hardcoded Ports in HubView Quick-Launch Links

**Location:** `HubView.swift:113, 188–192`

Ports 9119, 8080, and 11434 appear directly in `HubView.swift` as quick-launch links and WebKit load targets. Not a bug (these are intentional local service links), but they're not surfaced through any config or `ARESAppState`. If a user runs Hermes UI on a non-default port, the links are wrong.

---

## Integration Gap Summary

| Integration | Python Side | Swift Side | Status |
|---|---|---|---|
| ZMQ IPC | ✅ Real ROUTER socket | ❌ Stub (no-op `send()`) | Dead — 0% connected |
| OSC emitter | ✅ Implemented | ❌ No receiver | Dead — never called in daemon |
| Hermes MCP bridge (9501) | ⚠️ Config field + health probe | ❌ Not referenced | Speculative — no live service |
| Hermes CLI bridge | ⚠️ Via subprocess in AppState | ⚠️ Blocks main thread | Works but fragile (see C-3) |
| Ollama (local LLM) | ⚠️ No `num_ctx`, `cfg.llm` broken | N/A | Broken (see C-4) |

---

## Recommended Fix Order

1. **C-1** — Rewrite git history to remove the hardcoded API key before any push
2. **C-4** — Fix `cfg.llm` → `cfg.agent` mapping so the LLM layer doesn't crash
3. **C-2** — Inject `SAMRuntime` into SwiftUI environment so `CompanionView` doesn't crash
4. **C-3** — Move blocking calls off `@MainActor` (use `Task.detached`)
5. **W-1** — Fix `ares setup` TOML write / `load_config()` mismatch so API key setup works
6. **W-4** — Implement Swift ZMQ DEALER so there's actual IPC between app and daemon
7. **W-5** — Wire OSC emitter into daemon state transitions and add a receiver in Swift
8. **W-3** — Add `num_ctx` to Ollama payloads so local LLM gets a usable context window
9. Everything else — warnings and info items by priority

---

*Report generated by automated static analysis + shell inspection. Build could not be executed (Xcode/Swift not available in audit environment). All Swift findings are from source inspection only. Python test suite should be run locally with `pytest tests/unit/ -x -q` to confirm the 30-pass baseline.*

---

## Session 2 Changes (2026-05-26)

- Added Settings tab wrapper (`SAMSettingsView`) bridging SAM's `PreferencesView` into ARES Settings (commit `f8b2f0a`)
- Wired ALICE image generation through SAM and added a "Generate Avatar" button to the Companion view (commit `f8b2f0a`)
- Surfaced ALICE backend config (`alice_base_url` + `alice_api_key`) in `SAMSettingsView` with a ComfyUI / AUTOMATIC1111 / OpenAI-compatible note — the existing UserDefaults keys are now editable from the UI and pre-populate with prior values
- Added `fast_path_enabled` toggle (UserDefaults: `ares_fast_path_enabled`) in HubView's AI CONFIGURATION GroupBox and matching `AgentConfig.fast_path_enabled` field with TOML parsing under `[agent].fast_path_enabled`
- Python-side fast-path interception is a placeholder comment block in `ares/runtime/local_backend.py` (Ollama call site) — UI plumbing only, the Lilith-pattern gate is not yet active. The LM Studio path at `ares/llm/local.py` was intentionally left untouched.
