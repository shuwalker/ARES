# ARES Production v1.0 — Punch List

**Goal:** Every feature in the shipping app works. No dummy reachable in production. No dead code. Every UI surface verified against a real backend.

**Policy: cut or finish.** Each brick/feature below gets a verdict — FINISH (wire it for real) or CUT (remove the option/UI until it's real). No third state.

**Audit date:** 2026-06-10 · branch `production/v1.0` (from `feat/real-identity-memory`)

---

## A. Showstopper findings

### A1. The app never runs the production stack
`ARESRuntime` calls `ARESAppState.create(environment: environmentFromLaunchArgs())`, which defaults to `development` unless `ARES_ENV=production` is set in the app's environment. macOS apps launched from Finder don't inherit shell env vars — so **every normal launch runs all 11 bricks as dummies**. Chat works only because gateway providers bypass the stack.

**Fix:** environment must come from build configuration (`#if DEBUG`) or app settings, not an env var. Production = default for release builds.

### A2. The production preset can't fully succeed even when invoked
`BackendStack.production()` wires `.perceiver(.local)` and `.workflow(.filesystem)` — both hit `assertionFailure` + dummy fallback (crash in debug, silent dummies in release). `.voice(.kokoro)` silently substitutes SystemVoiceEngine.

**Fix:** preset must only reference implementations that exist (see verdicts below).

### A3. Tools are never given to the model
`ToolProvider` contract is solid (MCP-style, schemas, `requiresApproval`) and two real providers exist (N8N, NativeComputerControl/AppleScript) — but `listTools()`/`execute()` are called from **nowhere**. `BackendStack` has no tools slot; the chat services never do a tool-call round trip. Native ARES can talk but cannot act.

**Fix:** P1 below — the native agent loop.

### A4. Lying wiring log
`.brain(.local(model))` prints `✅ MLXAgentBrain using local model` but all three MLXAgentBrain methods are placeholders. ✅ must mean real.

---

## B. Brick-by-brick verdicts (11-brick stack)

| # | Brick | Real impls today | Stub paths | Verdict |
|---|---|---|---|---|
| 1 | GatewayProvider | Ollama, Hermes, Claude, OpenAI | Ollama `toolCall` "not implemented" | **FINISH** — add tool-call support (Ollama supports `tools` since 0.3; use `/api/chat`) |
| 2 | ReasoningBrain | HermesAgentBrain | MLX placeholders; `.claude` → dummy | **FINISH** ClaudeBrain + GatewayBrain (any gateway as brain); **CUT** MLX from v1.0 (remove `.local` case or alias to Ollama) |
| 3 | MemoryStore | SQLiteMemoryStore (+Ollama embeddings) | `.vectorDB` → dummy | **FINISH** sqlite; **CUT** vectorDB case |
| 4 | VoiceEngine | SystemVoiceEngine (TTS real, STT partial) | `.kokoro` → silent substitute; buffer-mode STT stub | **FINISH** system (incl. live STT via SFSpeechRecognizer); **CUT** kokoro case |
| 5 | Perceiver | none | `.local`/`.cloud` → dummy + assert | **FINISH minimal**: MicPerceiver (AVAudioEngine) since Companion needs ears; **CUT** cloud |
| 6 | WorldPerception | AppleVision, ScreenCapture | `.vision(model)` → dummy | **FINISH** the two real ones; **CUT** `.vision` case |
| 7 | Identity | FileSystemIdentity | — | **FINISH** (verify load/save round-trip) |
| 8 | Mimicry | RealisticMimicry | — | **FINISH** (verify it drives AvatarWidget) |
| 9 | EventBus | LocalEventBus, JROSEventBusBridge | `.zmq` → dummy | **FINISH** local + JROS (add schema contract test); **CUT** zmq |
| 10 | Workflow | none | `.filesystem` → dummy + assert | **FINISH minimal** FileSystemWorkflow (JSON in app support) — Kanban/Workflows views need it |
| 11 | Scheduler | NativeMacScheduler | `.launchctl`, `.hermes` → dummy | **FINISH** nativeMac; **CUT** other cases |
| 12 | Embodiment | DesktopEmbodiment | — | **FINISH** (verify voice/face state transitions) |
| — | ToolProvider | N8N, NativeComputerControl | not in stack, never called | **FINISH** — add to BackendStack + agent loop (P1) |

**Rule enforced at the end:** grep for `assertionFailure("[WIRING]` returns zero hits; every `case` in every `*Impl` enum constructs a real implementation or doesn't exist.

---

## C. Work plan (priority order)

### P1. Native agent loop (the core gap)
1. Add `tools: [any ToolProvider]` to `BackendStack` + builder method.
2. New `ToolRouter` service: aggregates `listTools()` across providers, namespaced `provider.tool`.
3. Extend gateway chat round trip: send tool schemas → detect tool-call response → route to `ToolRouter.execute` → append result → continue until final text. (Ollama `/api/chat` tools, Claude `tool_use` blocks, OpenAI `tool_calls`; Hermes runs its own loop server-side — skip.)
4. Stream tool activity into the Thought Stream UI.

### P2. Approval layer
1. `ApprovalBroker` (MainActor): `requiresApproval` tools suspend until user confirms.
2. Sheet UI: tool name, provider, JSON input pretty-printed, Allow / Allow always (per-tool allowlist in UserDefaults) / Deny.
3. Default-deny for `category: .system` and AppleScript execution.

### P3. Fix environment resolution (A1)
Release builds default to production stack; Settings toggle for "Safe mode (dummies)" for debugging; visible badge when any dummy is live.

### P4. Finish the FINISH list / retire the CUT list (section B)
Includes deleting dead enum cases, the assertionFailure fallbacks, and making ✅ logs truthful.

**Cut = preserve, then remove.** Nothing is destroyed: before deletion, every cut file is copied to `attic/v1.0-cuts/` at the repo root (outside all build targets) with a README mapping each file to its origin commit, the reason for the cut, and restore steps. Git history is the second safety net.

### P5. UI verification pass (every view, real data)
Hub, Companion (chat+avatar+voice), Kanban, Terminal, SSH, Files, Sessions, Skills, Workflows, Automations, CronJobs, Connections, Office, Studio, Usage, Overview, Settings. Each: drive it against a live backend, fix or cut. Track in checklist below.

### P6. Dead code & repo hygiene
- Remove committed build products: `ARES.app/` bundles (repo root + ARES-Desktop), `.build/`, `.claude/worktrees/` from tracking; extend `.gitignore`.
- Delete `diff_output.txt` at GitHub folder root (not in repo but noted).
- Rewrite `CLAUDE.md` — it documents a deleted Python codebase.
- Reconcile `VERSION` (0.0.0) vs README (v0.2.0) vs ARCHITECTURE.md (v0.1.0).

### P7. Tests & CI gate
- Contract test per brick (real impl satisfies contract semantics, not just compiles).
- JROS bridge schema golden-file test against JROS v0.2.3 message format.
- `swift test` green required before any merge to main.

---

## D. UI verification checklist (P5)

| View | Backend it needs | Status |
|---|---|---|
| Companion chat | any gateway | ☐ |
| Companion avatar states | Mimicry + Embodiment | ☐ |
| Voice in/out | SystemVoiceEngine + MicPerceiver | ☐ |
| Hub | EventBus | ☐ |
| Kanban | Workflow (new FS impl) or JROS | ☐ |
| Terminal / SSH | local pty / NIOSSH | ☐ |
| Files | FileEditorService | ☐ |
| Sessions | SwiftData store | ☐ |
| Skills | SkillBrowserService (Hermes/JROS) | ☐ |
| Workflows / Automations / CronJobs | services + Scheduler | ☐ |
| Connections | ConnectionProfile store | ☐ |
| Usage | UsageBrowserService | ☐ |
| Overview / Office / Studio | finish or cut decision per view | ☐ |
| Settings | all toggles do something real | ☐ |

---

## E. Build loop

Claude writes code on `production/v1.0`; Matthew runs locally:

```bash
cd ~/GitHub/ARES/ARES-Desktop
swift build 2>&1 | tail -30      # paste failures back
swift test 2>&1 | tail -30
```

No merge to main until: zero dummies reachable in release config, P1–P4 done, P5 checklist fully checked.
