# ARES — Modular AI Framework Architecture

**v0.1.0 — Clean Production Release**

This document defines the canonical architecture of ARES: what is framework, what is functional, and how the system is organized.

---

## Repository Structure (Clean)

```
ARES/
├── ARES-Desktop/                    # The complete app (iOS/macOS)
│   ├── Sources/
│   │   ├── ARESCore/                # FRAMEWORK LAYER (reusable, protocol-based)
│   │   │   ├── Contracts/           # 14 protocol definitions (bricks)
│   │   │   │   ├── GatewayProvider.swift      # LLM abstraction
│   │   │   │   ├── Embodiment.swift          # Avatar/body control
│   │   │   │   ├── Perceiver.swift           # Sensor input
│   │   │   │   ├── MemoryStore.swift         # Knowledge persistence
│   │   │   │   ├── VoiceEngine.swift         # Speech I/O
│   │   │   │   ├── ReasoningBrain.swift      # Planning & reasoning
│   │   │   │   ├── PersonaProvider.swift     # Personality traits
│   │   │   │   ├── ToolProvider.swift        # Capability execution
│   │   │   │   ├── Identity.swift            # Self-model
│   │   │   │   ├── Mimicry.swift             # Animation driver
│   │   │   │   ├── WorldPerception.swift     # Scene understanding
│   │   │   │   ├── EventBus.swift            # Pub/sub coordination
│   │   │   │   ├── Workflow.swift            # Task visualization
│   │   │   │   ├── Scheduler.swift           # Job scheduling
│   │   │   │   └── AnyCodable.swift          # JSON codec
│   │   │   │
│   │   │   ├── Dummies/             # 14 safe default implementations
│   │   │   │   ├── DummyGatewayProvider.swift
│   │   │   │   ├── DummyEmbodiment.swift
│   │   │   │   ├── DummyPerceiver.swift
│   │   │   │   ├── DummyMemoryStore.swift
│   │   │   │   ├── DummyVoiceEngine.swift
│   │   │   │   ├── DummyReasoningBrain.swift
│   │   │   │   ├── DummyPersonaProvider.swift
│   │   │   │   ├── DummyToolProvider.swift
│   │   │   │   ├── DummyIdentity.swift
│   │   │   │   ├── DummyMimicry.swift
│   │   │   │   ├── DummyWorldModel.swift
│   │   │   │   ├── DummyEventBus.swift
│   │   │   │   ├── DummyWorkflow.swift
│   │   │   │   └── DummyScheduler.swift
│   │   │   │
│   │   │   ├── Models/              # Shared data types (used by contracts)
│   │   │   └── Services/            # Utilities & helpers
│   │   │
│   │   └── ARES/                     # FUNCTIONAL LAYER (the app)
│   │       ├── App/
│   │       │   ├── ARESApp.swift              # @main entry
│   │       │   ├── ARESAppState.swift        # State machine
│   │       │   ├── ARESRuntime.swift         # Backend initialization
│   │       │   └── ARESAppDelegate.swift     # Lifecycle
│   │       │
│   │       ├── Providers/           # Concrete gateway implementations
│   │       │   ├── OllamaGatewayProvider.swift    # Pure LLM (localhost:11434)
│   │       │   └── HermesGatewayProvider.swift    # Full agent (localhost:8642)
│   │       │
│   │       ├── Widgets/             # Composable UI pieces
│   │       │   ├── ChatWidget.swift               # Streaming chat
│   │       │   ├── BackendPickerWidget.swift      # Ollama ↔ Hermes switcher
│   │       │   ├── PerceptionWidget.swift         # Camera + vision
│   │       │   ├── AvatarWidget.swift             # Emotion states
│   │       │   └── HistoryWidget.swift            # Session list
│   │       │
│   │       ├── Views/
│   │       │   ├── DashboardView.swift            # Main dashboard
│   │       │   ├── ARESRootView.swift             # Tab navigation
│   │       │   ├── CompanionView.swift            # Companion interface
│   │       │   ├── OfficeView.swift               # Workspace
│   │       │   ├── HubView.swift                  # System hub
│   │       │   └── SettingsView.swift             # Configuration
│   │       │
│   │       ├── Services/
│   │       │   ├── WiringBuilder.swift            # Backend factory
│   │       │   ├── Wiring.swift                   # Backend resolver
│   │       │   ├── CompanionChatService.swift     # Chat business logic
│   │       │   └── [other services]
│   │       │
│   │       ├── Bootstrap/           # Dependency detection
│   │       ├── Models/              # View models
│   │       └── Resources/           # Assets
│   │
│   └── Tests/
│       └── ARESTests/               # Swift test suite (9 tests, all passing)
│
├── docs/
│   ├── MODULAR_ARCHITECTURE.md      # Framework design patterns
│   ├── archive/                     # Historical documentation
│   ├── prompts/                     # Reference prompts
│   └── recipes/                     # Usage examples
│
├── Package.swift                    # Swift Package Manager manifest
├── Package.resolved                 # Dependency lock file
├── README.md                        # Project overview
├── CLAUDE.md                        # Development guide
├── VERSION                          # Version number
├── Info.plist.template              # App bundle template
└── install.sh                       # Installation helper

```

---

## Design Principles

### 1. One Concern Per Brick
Each protocol defines exactly one concern. Modules don't mix responsibilities.

### 2. Protocol-Based Modularity
- Contracts live in `ARESCore/Contracts/`
- Implementations live in `ARESCore/Dummies/` or `ARES/Providers/`
- Never import concrete classes; always import protocols

### 3. Wiring Layer Owns Concretions
`WiringBuilder.swift` is the **only place** that knows which implementation plugs into which protocol.
```swift
let stack = BackendBuilder()
    .embodiment(.desktop)
    .brain(.hermes(url: "http://localhost:8642"))
    .build(checkProduction: true)
```

Swap a brick by changing one line:
```swift
.brain(.hermes(...))  // Use Hermes agent
.brain(.local(...))   // Use local inference
```

### 4. Production Safety
- Production mode **rejects dummies** with `WiringError.productionWithDummies`
- Development mode defaults to all dummies
- If dummies slip into production, a 60-second warning timer fires repeatedly

### 5. Async/Streaming First
All I/O is async. All conversation is streaming. No blocking calls.

### 6. Sendable Everywhere
Swift 6 strict concurrency: all protocols are `Sendable`.

---

## What Is Framework vs Functional

### Framework (ARESCore/Contracts/ + ARESCore/Dummies/)
- **14 protocol contracts** — define "what any brick must do"
- **14 dummy implementations** — safe defaults for testing & development
- **Zero business logic** — no Hermes URLs, no model names, no views
- **Reusable** — another app could use ARESCore unchanged
- **Stable** — changes here affect 30+ files downstream

### Functional (ARES/)
- **Providers** — concrete Ollama, Hermes, Claude implementations
- **Widgets** — ChatWidget, AvatarWidget, BackendPickerWidget (UI pieces)
- **Views** — Dashboard, CompanionView, HubView (full screens)
- **Services** — WiringBuilder, CompanionChatService (business logic)
- **Models** — view data structures (ARESChatModels, etc.)
- **Bootstrap** — app startup and dependency detection

**Key rule:** Framework never imports from ARES/. ARES imports from ARESCore.

---

## Backend Selection: Ollama vs Hermes

The **BackendPickerWidget** clarifies the fundamental choice:

### Ollama (Pure LLM, No Tools)
- Raw language model inference only
- No memory, no tools, no services
- Fast, lightweight, runs locally (localhost:11434)
- **Use for:** Thinking engine, reasoning-only system

### Hermes (Independent Agentic Framework)
- Full agent with tools, memory, skills, multi-turn reasoning
- Can invoke filesystem, web, code execution, custom tools
- Persistent sessions and episodic memory
- Can delegate to Ollama internally
- **Use for:** Autonomous system that acts, not just thinks

---

## File Management Rules

### Keep at Root
- `Package.swift` — SPM manifest (framework definition)
- `Package.resolved` — dependency lock
- `README.md` — public overview
- `CLAUDE.md` — development guide
- `VERSION` — canonical version number
- `Info.plist.template` — app bundle metadata
- `install.sh` — installation helper

### Keep in docs/
- `MODULAR_ARCHITECTURE.md` — (this file)
- `prompts/` — reference prompts
- `recipes/` — usage examples

### Archive in docs/archive/
- All superseded architecture docs
- All interim design documents
- All historical audit trails

### Delete (Dead Code)
- `pyproject.toml` — Python config for deleted ares package
- `tools/` — obsolete collaboration scripts
- `scripts/` — speculative hardware MCP servers
- `tests/` (Python) — all import deleted ares package
- `governance/` — policy documents not actively used

---

## Build & Run

```bash
# Clean build
swift build

# Run tests
swift test

# Development (all dummies, no external services needed)
ARES_ENV=development swift run ARES

# Production (real backends required)
ARES_ENV=production HERMES_URL=http://localhost:8642 swift run ARES
```

---

## Summary

ARES is a **modular framework** with a **functional app**:
- **Framework**: 14 contracts + 14 dummies in ARESCore (swappable, stable)
- **Functional**: App logic, views, providers in ARES (specific, evolving)
- **Wiring**: BackendBuilder makes it easy to swap any brick
- **Production**: Rejects misconfiguration; fails loudly, never silently

Everything else is archived or deleted. The codebase is clean, the build is fast, and the system is ready to grow.

---

**Status:** ✅ Clean, modular, production-ready  
**Build:** 0.34s, 0 errors  
**Tests:** 9/9 passing  
**Last update:** 2026-06-07
