# CLAUDE.md — ARES Development Guide

For AI contributors. This file describes what actually exists. The old Python codebase (`ares/` package, `pyproject.toml`, pytest) is **deleted** — ARES is now a pure Swift project.

## What ARES Is

ARES = Autonomous Reasoning & Execution System. A native macOS **Mission Control for AI**: chat, avatar, voice, terminal, files, kanban, skills, and automation in one SwiftUI app.

- ARES is the **front end** of the Jenkins Robotics stack. **JROS is the back end** — but it's swappable like any other provider, not hardcoded.
- Modular "bricks" architecture: every capability is a protocol; implementations plug in via wiring.
- **Local-first.** The user owns their data. No cloud-only paths, no phoning home.

## Architecture

Two Swift targets under `ARES-Desktop/Sources/`:

- **ARESCore** (framework layer, zero business logic)
  - `Contracts/` — 15 protocol contracts (GatewayProvider, ReasoningBrain, MemoryStore, VoiceEngine, Perceiver, WorldModel, Identity, Mimicry, EventBus, KanbanBoard, CronScheduler, ToolProvider, PersonaProvider, Embodiment, ResourceProvider)
  - `Dummies/` — safe no-op implementations, **dev only**
  - `Models/`, `Services/` — shared types and utilities (incl. ToolRegistry, Hub readers)
- **ARES** (app layer)
  - `App/` — entry point, ARESAppState, ARESRuntime, app delegate
  - `Providers/` — concrete brick implementations (Ollama, Hermes, Claude, OpenAI gateways; JROS bridges; system voice; Apple Vision; storage)
  - `Services/` — business logic (WiringBuilder, CompanionChatService, Agent/, SSH/, Terminal/, Storage/)
  - `Views/` — full screens (Companion, Hub, Kanban, Terminal, Files, Settings, …) with composable widgets in `Views/Widgets/`

**Wiring philosophy:** `Services/WiringBuilder.swift` is the **only** place that maps protocols to implementations. Three tiers, in order:

1. Configured provider (JROS / Hermes / Ollama / Claude / OpenAI)
2. Built-in native fallback (system TTS, SQLite memory, local event bus, …)
3. Dummies — development only; **rejected in production builds**

## Agent Loop

- `Services/Companion/CompanionChatService.swift` runs a multi-round tool loop: send tool schemas → model returns tool calls → execute → feed results back → repeat until final text.
- `Services/Agent/ToolRouter.swift` + `ARESCore/Services/ToolRegistry.swift` aggregate ToolProviders and expose them to tool-capable gateways.
- `Services/Agent/ApprovalBroker.swift` gates any tool with `requiresApproval` or `category: .system` behind a user consent sheet. Per-tool allowlist lives in UserDefaults key `ARES.approval.allowlist`.

## Build & Test

```bash
cd ARES-Desktop
swift build
swift test
```

- macOS 14+, Swift 6.1+ (strict concurrency, Sendable everywhere).
- Release builds default to the **production stack**. Override with `ARES_ENV` or UserDefaults `ARES.safeMode`.

## Git Rules

- **Main is protected.** Feature branches only; never commit to main directly.
- Current production push happens on branch `production/v1.0`.
- `PRODUCTION_PLAN.md` is the source of truth: punch list, brick-by-brick verdicts, and the **cut-or-finish policy** (every feature is either wired for real or removed — no half-states).
- `attic/v1.0-cuts/` preserves cut code. **Never delete code without atticing it first.**

## External Stack

| Service | Location | Notes |
|---|---|---|
| JROS | `~/GitHub/JROS` | Robotics back end; Unix socket `/tmp/ares_jros.sock` |
| Hermes | `~/.hermes` | Agent gateway, `localhost:8642` |
| Ollama | `localhost:11434` | Local LLM inference |
| n8n | `localhost:5678` | Workflow automation (ToolProvider) |

All optional — ARES must degrade to native built-ins when they're absent.

## What Will Break Things

- Editing an ARESCore contract without updating **all** conformers (dummies + providers + JROS bridges).
- Adding wiring enum cases without real implementations — violates cut-or-finish; no `assertionFailure` fallbacks to dummies.
- Committing `.build/` or `*.app` bundles (gitignored; keep it that way).
- Bypassing ApprovalBroker for system-category or approval-required tools.
- Cloud-only dependencies without a local fallback.
- Deleting code without copying it to `attic/v1.0-cuts/` first.

## Owner

Matthew Jenkins (shuwalker) · Mac Studio (primary) · Built by Jenkins Robotics.
