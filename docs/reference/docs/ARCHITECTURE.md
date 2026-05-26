# ARES Architecture (Current — May 2026)

## What ARES Is

ARES is an autonomous reasoning and execution system for Jenkins Robotics.
It has a Python **brain** (cognitive loop, personality, memory, MCP tools)
and a Swift **face** (native macOS app with cinematic avatar + cognitive
instrumentation). They talk over WebSocket.

The brain thinks. The face renders **and shows what the brain is doing**.

> Looking for the cognition / memory / DAG / shader-bindings layer? See
> [`COGNITIVE_OS.md`](./COGNITIVE_OS.md). This document covers the
> larger system; COGNITIVE_OS is the single-source reference for the
> Phase 0 → 4 work that landed in PR #2.

## System Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                        Mac Studio (M1 Max)                          │
│                                                                      │
│  ┌─────────────────────────────┐  ┌─────────────────────────────┐  │
│  │      Python Brain           │  │      Swift Face             │  │
│  │      (ares serve :7860)     │  │      (ARES.app)             │  │
│  │                             │  │                              │  │
│  │  ┌───────────────────┐     │  │  ┌────────────────────┐     │  │
│  │  │  Cognitive Loop   │     │  │  │  RealityKit Scene   │     │  │
│  │  │  PERCEIVE→THINK→  │     │  │  │  ┌──────┐ ┌──────┐│     │  │
│  │  │  ACT→REFLECT      │     │  │  │  │Avatar│ │Eng.Mdl││     │  │
│  │  └───────┬───────────┘     │  │  │  │(Metal│ │(PBR/ ││     │  │
│  │          │                 │  │  │  │Shader│ │USDZ) ││     │  │
│  │  ┌───────▼───────────┐    │  │  │  └──────┘ └──────┘│     │  │
│  │  │  Core Modules      │    │  │  └────────────────────┘     │  │
│  │  │  • personality.py  │    │  │  ┌────────────────────┐     │  │
│  │  │  • identity.py     │    │  │  │  Personality Panel  │     │  │
│  │  │  • face_state.py   │    │  │  │  Status Dashboard  │     │  │
│  │  │  • cognitive.py    │    │  │  │  Chat Stream        │     │  │
│  │  │  • memory.py       │    │  │  │  Command Bar + Mic  │     │  │
│  │  │  • bus.py (ZMQ)    │    │  │  └────────────────────┘     │  │
│  │  └────────────────────┘    │  │                              │  │
│  │                             │  │  ┌────────────────────┐     │  │
│  │  ┌───────────────────┐     │  │  │  VoiceManager      │     │  │
│  │  │  Hermes Bridge    │◄────┼──┼──►│  (AVFoundation)    │     │  │
│  │  │  (connects to      │     │WS│  └────────────────────┘     │  │
│  │  │   Hermes agent)    │     │  │                              │  │
│  │  └────────────────────┘     │  │  ┌────────────────────┐     │  │
│  │                             │  │  │  MenuBarExtra      │     │  │
│  │  ┌───────────────────┐     │  │  │  (always on)        │     │  │
│  │  │  MCP Server       │     │  │  └────────────────────┘     │  │
│  │  │  (8 tools exposed)│     │  │                              │  │
│  │  └────────────────────┘     │  │                              │  │
│  │                             │  └─────────────────────────────┘  │
│  │  ┌───────────────────┐     │                                    │
│  │  │  FastAPI Server    │     │                                    │
│  │  │  REST + WebSocket  │◄────┼── WebSocket :7860                │
│  │  │  (8 endpoints)     │     │                                    │
│  │  └────────────────────┘     │                                    │
│  └─────────────────────────────┘                                    │
│                                                                      │
│  ┌─────────────────────────────┐  ┌────────────────────────────┐  │
│  │  Hermes Agent               │  │  JP01 Robot (USB/Serial)   │  │
│  │  (existing, :9520 MCP)      │  │  (6-DOF arm, future)       │  │
│  └─────────────────────────────┘  └────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────────┘
```

## Python Brain (ares/)

### Entry Points

| File | Lines | Purpose |
|------|-------|---------|
| `cli.py` | 776 | CLI: `ares serve`, `ares mcp`, `ares doctor` |
| `api.py` | ~900 | FastAPI server: REST + WebSocket; cognitive / memory / idle endpoints |
| `mcp_serve.py` | 514 | MCP server: 8 tools for external AI clients |
| `__main__.py` | — | `python -m ares` entry |

### Core Modules (ares/core/)

| File | Lines | Purpose |
|------|-------|---------|
| `bus.py` | 474 | ZMQ pub/sub bus — 9 channels (brain_output, face_state, audio_raw, audio_processed, system, mcp_bridge, robot_command, robot_sensor, memory) |
| `cognitive.py` | ~600 | 4-phase cognitive loop: PERCEIVE → THINK → ACT → REFLECT with guidance matrix, stop hooks, `on_phase_change` observer, and per-cycle reasoning DAG via `ThoughtNodeRecord` + `emit_thought_node()` |
| `personality.py` | 325 | 4-layer personality: HEXACO traits → SPECIAL traits → Expression style → Domain weights. Generates system prompts |
| `identity.py` | — | Who ARES is — values, name, backstory |
| `face_state.py` | — | FaceState enum (idle, thinking, speaking, happy, angry, neutral) + intensity mapping |
| `idle.py` | ~250 | Idle reflexion: consolidate episodics, dedupe semantic facts, surface unresolved questions. See [`COGNITIVE_OS.md`](./COGNITIVE_OS.md#phase-3--idle-reflexion). |
| `memory.py` | 197 | Legacy persistent memory layer (kept as audit log; primary store is `ares/memory_store.py`) |

### Runtime (ares/runtime/)

| File | Lines | Purpose |
|------|-------|---------|
| `hermes_bridge.py` | 195 | HTTP server on :9876 — bridges Swift `/api/chat` to Hermes (current `cognition_query()` is a stub; real wiring is owned by a sibling PR) |
| `ares_bridge_minimal.py` | 49 | Reference: shells out to `hermes -z <text>`. The pattern the bridge will adopt once wired |
| `brain_transport.py` | — | Transport abstraction for LLM calls |
| `session_store.py` | ~50 | Volatile per-session turn deque (capacity 12). Used by `/api/chat`. |
| `launcher.py` | 147 | Process launcher; resolves Hermes binary (`find_hermes()`) and reports status (`hermes_status()`) |
| `bootstrap.py` | — | First-run setup |
| `env_detector.py` | — | Environment detection (GPU, display, platform) |

### Memory (ares/memory_store.py)

Tiered memory store added in Phase 1. SQLite source-of-truth at
`~/.ares/memory.db` with two tables (`episodics`, `facts`) and a
swappable `VectorStore` / `Embedder` protocol pair. Ships with
`InMemoryVectorStore` + `DeterministicEmbedder` defaults (no external
deps) and an opt-in `OllamaEmbedder`. See
[`COGNITIVE_OS.md`](./COGNITIVE_OS.md#phase-1--tiered-memory).

### Models (ares/models/)

| File | Lines | Purpose |
|------|-------|---------|
| `system.py` | — | System models (config, state) |
| `cognitive.py` | ~80 | `CognitiveSnapshot` transport contract — `LoopBlock`, `ThoughtBlock`, `ThoughtNode`, `MemoryHitBlock`. Versioned via `SCHEMA_VERSION`; forward-compatible decode. |
| `engineering.py` | 177 | Engineering models (CAD, simulations, robot joints) |
| `project.py` | — | Project tracking models |

### Skills (ares/skills/)

| File | Lines | Purpose |
|------|-------|---------|
| `cognitive/avatar_server.py` | — | Avatar state server |
| `cognitive/perception_server.py` | — | Perception processing |
| `cognitive/vts_controller.py` | 325 | Voice-to-speech controller |
| `cognitive/reference/stt_whisper_simple.py` | — | Whisper STT reference |
| `cognitive/reference/tts_kokoro.py` | — | Kokoro TTS reference |
| `physical/robot.py` | — | Robot control interface |
| `desktop/desktop.py` | — | Desktop control interface |

### Other Modules

| File | Lines | Purpose |
|------|-------|---------|
| `config.py` | 177 | Configuration loading and defaults |
| `daemon.py` | 267 | Daemon mode for background operation |
| `reasoning.py` | 247 | Reasoning engine (chain-of-thought) |
| `discovery.py` | 233 | Service discovery |
| `memory.py` | 228 | Memory management |
| `sync.py` | — | Data synchronization |
| `audit.py` | — | Audit logging |
| `workflows/youtube.py` | 719 | YouTube pipeline workflow |
| `tasks/executor.py` | 212 | Task execution engine |
| `tasks/queue.py` | — | Priority task queue |
| `tools/registry.py` | 208 | Tool registry |
| `tools/n8n.py` | 314 | n8n workflow integration |
| `llm/router.py` | — | LLM provider router |
| `llm/cloud.py` | — | Cloud LLM (OpenAI, Anthropic) |
| `llm/local.py` | — | Local LLM (LM Studio) |

**Total Python LOC (non-reference): ~8,293**

## Swift Face (`ARES-Face/`)

### Current state: shipped (RealityKit + Metal)

The Canvas POC described in earlier revisions of this doc has been
replaced. The active app is `ARES-Face/` — SwiftUI + RealityKit +
`CustomMaterial` Metal shaders. Six switchable avatar styles, all
working. The old POC code lives under `ares/reference/swift-ui/` for
historical reference only.

For the full build spec see
[`BUILD_SPEC_FACE_APP.md`](./BUILD_SPEC_FACE_APP.md); for the
rendering pipeline see
[`RENDERING_ARCHITECTURE.md`](./RENDERING_ARCHITECTURE.md).

| Directory | Contents |
|---|---|
| `App/` | `ARESApp.swift` (`@main`), `ARESRootView.swift` (root layout, sidebar mount, operator-page routing) |
| `Models/` | `AgentState`, `AvatarExpression`, `AvatarStyle` (6 styles), `ImmersionLevel`, `ARESMessage`, `FaceConfig`, `CognitiveSnapshot` (Codable mirror of the Pydantic contract) |
| `Networking/` | `BrainConnection.swift` — WebSocket client to `:7860/ws`, REST fallback, decodes `cognitive_snapshot` events into `@Published cognitive` |
| `Rendering/` | `AvatarRenderer.swift` (CustomMaterial creation, uniform updates), `AvatarEntity.swift`, `SceneSetup.swift`, `CognitiveBindings.swift` (pure-function snapshot→uniform table — Phase 4) |
| `Shaders/` | `SharedHeader.h` (uniform structs, Swift↔Metal bridge), six paired surface + geometry shaders (`BlackFire`, `Anime`, `Hologram`, `Blob`, `PixelVolume`, `Constellation`) |
| `Views/` | `AvatarSceneView`, `ChatStream`, `CommandBar`, `ImmersionBar` (with heartbeat pill), `SidebarView` (8 tabs, routed), `CognitiveActivityPanel`, `MemoryInspectorView`, `MissionControlPanel`, `MenuBarView`, `DashboardPage` (enum) |
| `Voice/` | `VoiceManager.swift` — AVFoundation mic + NSSpeechRecognizer |

### Cognitive instrumentation in the UI

- **Heartbeat pill** in `ImmersionBar` → tap → `CognitiveActivityPanel`
  full panel. Subscribes to `cognitive_snapshot` over WebSocket.
- **Sidebar** `.sessions` → `MemoryInspectorView` (list + recall +
  delete).
- **Sidebar** `.logs` → `MissionControlPanel` (force-directed reasoning
  DAG, SwiftUI `Canvas` + Verlet integrator, ~60 fps).
- **Avatar shaders** consume cognition uniforms (`emissivePulse`,
  `glitchAmplitude`, `noiseScale`, `vertexJitter`) bound from the
  snapshot via `CognitiveBindings.evaluate`.

### Reference / legacy

The old POC and Swift backend lives under `ares/reference/swift-ui/`
(810-line monolithic `ARESApp.swift` with Canvas rendering, plus a
`mac_sources/ARES-Mac/` macOS-specific build). Historical reference
only — do not extend; `ARES-Face/` is the active app.

## Communication Protocols

### WebSocket (Brain ↔ Face)

The primary channel. Brain at `ws://localhost:7860/ws`, Face connects as client.

```json
// Face → Brain
{"action": "chat", "text": "status of JP01 build", "session_id": "..."}
{"action": "set_personality", "layer": "hexaco", "trait": "openness", "value": 0.7}
{"action": "set_face_state", "state": "thinking"}
{"action": "get_cognitive_snapshot"}
{"action": "ping"}

// Brain → Face
{"type": "face_state", "state": "thinking", "config": {...}}
{"type": "chat_response", "text": "JP01 is at phase 3..."}
{"type": "personality_change", "layer": "hexaco", "trait": "openness", "value": 0.7}
{"type": "cognitive_snapshot", "schema_version": 1, "running": true,
 "loop": {"cycle": 4, "phase": "think", "urgency": "medium", ...},
 "thought": {"summary": "reflect", "depth": 4, "branches": [...]},
 "memory_recall": [{"id": "...", "score": 0.81, "text": "...", "kind": "episodic"}],
 "errors": []}
{"type": "pong", "timestamp": 1715632800.123}
```

The `cognitive_snapshot` message is pushed on every loop phase
transition plus after each `/api/chat` exchange. See
[`COGNITIVE_OS.md`](./COGNITIVE_OS.md#data-model-cognitivesnapshot)
for the full schema.

### ZMQ Bus (Internal Brain)

Nine channels for internal module communication:

| Channel | Direction | Purpose |
|---------|-----------|---------|
| `brain_output` | Cognitive → All | LLM responses, decisions |
| `face_state` | Cognitive → Face | Face state updates |
| `audio_raw` | Mic → STT | Raw audio frames |
| `audio_processed` | STT → Cognitive | Transcribed text |
| `system` | All | System events, errors |
| `mcp_bridge` | MCP ↔ Cognitive | External tool calls |
| `robot_command` | Cognitive → Robot | Servo commands |
| `robot_sensor` | Robot → Cognitive | Sensor readings |
| `memory` | Cognitive ↔ Memory | Memory read/write |

### MCP Server (External Clients)

Eight tools exposed via MCP for Claude Code, Cursor, other AI clients:

1. `ares_think` — Trigger cognitive cycle
2. `ares_status` — Get system status
3. `ares_personality_get` — Read personality
4. `ares_personality_set` — Modify personality
5. `ares_face_state` — Set avatar state
6. `ares_memory_search` — Search memories
7. `ares_memory_store` — Store memory
8. `ares_robot_command` — Send robot command

## Hardware Target

```
Mac Studio (M1 Max)
├── GPU: 24-core Apple GPU (Metal 4)
├── RAM: 32 GB unified memory
├── Display: 4K @ 60Hz (LG UltraFine)
├── Xcode 26.5, Swift 6.3.2
├── Frameworks: Metal, MetalKit, MPS, MPSGraph, RealityKit, SceneKit, ARKit
└── Connected: Ubiquiti network (10.15.0.9), NAS
```

## Project Directory Layout

```
ARES-Autonomous-Reasoning-Execution-System/
├── ares/
│   ├── __init__.py
│   ├── __main__.py              # python -m ares
│   ├── cli.py                   # CLI entry (ares serve, ares mcp, ares doctor)
│   ├── api.py                   # FastAPI server + WebSocket
│   ├── mcp_serve.py             # MCP server (8 tools)
│   ├── config.py                # Configuration
│   ├── daemon.py                 # Background daemon
│   ├── reasoning.py              # Reasoning engine
│   ├── memory.py                 # Memory management
│   ├── audit.py                  # Audit logging
│   ├── sync.py                   # Data sync
│   ├── discovery.py              # Service discovery
│   ├── core/
│   │   ├── bus.py                # ZMQ pub/sub (9 channels)
│   │   ├── cognitive.py          # 4-phase cognitive loop
│   │   ├── personality.py        # 4-layer personality system
│   │   ├── identity.py           # Who ARES is
│   │   ├── face_state.py         # Face state machine
│   │   └── memory.py             # Persistent memory
│   ├── runtime/
│   │   ├── hermes_bridge.py      # Bridge to Hermes agent
│   │   ├── brain_transport.py    # LLM transport
│   │   ├── launcher.py           # Process launcher
│   │   ├── bootstrap.py          # First-run setup
│   │   └── env_detector.py       # Environment detection
│   ├── models/
│   │   ├── system.py             # System models
│   │   ├── engineering.py        # CAD/sim/robot models
│   │   └── project.py            # Project tracking
│   ├── skills/
│   │   ├── cognitive/            # Perception, VTS, STT/TTS
│   │   └── physical/             # Robot, desktop
│   ├── embodiment/
│   │   ├── desktop/              # Desktop embodiment
│   │   └── robot/                # Robot embodiment
│   ├── llm/
│   │   ├── router.py             # Provider router
│   │   ├── cloud.py              # Cloud LLM
│   │   └── local.py              # Local LLM
│   ├── tasks/
│   │   ├── executor.py            # Task execution
│   │   └── queue.py               # Priority queue
│   ├── tools/
│   │   ├── registry.py            # Tool registry
│   │   └── n8n.py                  # n8n integration
│   └── workflows/
│       └── youtube.py             # YouTube pipeline
├── ares/reference/
│   ├── swift-ui/                  # POC Swift app (Canvas renderer)
│   │   ├── ARESApp.swift          # 810 lines - main app
│   │   ├── BlackFireSystem.swift  # Fire renderer POC
│   │   ├── VoiceManager.swift     # Mic input
│   │   ├── Package.swift          # SPM config
│   │   └── mac_sources/           # macOS-specific build
│   │       └── ARES-Mac/          # 12 files, ~700 lines
│   ├── docs/                      # Architecture and research docs
│   ├── lilith-ai/                 # Reference (lilith AI personality system)
│   ├── voicellm/                  # Reference (voice LLM pipeline)
│   └── deprecated-agent/          # Reference (old orchestrator, superseded)
└── pyproject.toml                 # Project config
```

## REST endpoints (current)

System
- `GET /api/status`, `GET /api/services`, `GET /api/identity`

Personality + face
- `GET /api/personality`, `POST /api/personality`, `GET /api/personality/prompt`
- `GET /api/face`, `POST /api/face`, `GET /api/face/states`

Chat
- `POST /api/chat` — writes episodic + session, pushes a fresh
  `cognitive_snapshot` over the WS

Cognitive loop
- `POST /api/cognitive/start`, `POST /api/cognitive/stop`
- `GET /api/cognitive/status` → `CognitiveSnapshot`

Memory inspector
- `GET /api/memory/episodics?limit=`
- `GET /api/memory/facts?limit=`
- `POST /api/memory/recall` `{query, k}`
- `DELETE /api/memory/episodics/{id}`

Idle reflexion
- `POST /api/idle/run` → `IdleReport`
- `GET /api/idle/last_report`

## Build Priority (What's Next)

**Shipped recently** ✅
- Phase 0–4 Cognitive OS (see [`COGNITIVE_OS.md`](./COGNITIVE_OS.md))
- ARES-Face SwiftUI app with 6 RealityKit + Metal shader styles
- Unit-test scaffold + GitHub Actions CI (Py 3.11 + 3.12, ruff + black)
- 46 unit tests passing

**Next** 🔨
1. **Hermes bridge v2** — replace `hermes_bridge.cognition_query()` stub
   with a real call. Owned by a sibling agent PR. Snapshot's
   `memory_recall` is the contract they'll consume.
2. **Concrete `VectorStore` implementations** — `SqliteVssStore`,
   `LanceDbStore`, `ChromaDbStore`. Protocol is shipped; pick one.
3. **Voice pipeline** — STT mic → brain → TTS speaker
4. **Operator-tab build-out** — `.models`, `.skills`, `.cron`,
   `.analytics` dashboard pages (sidebar mounted, pages stubbed)
5. **DAG replay scrubber** — persistence layer shipped; UI to scrub
   a stored cycle's reasoning trace forward/back
6. **Robot control** — JP01 servo commands over bus
7. **Install** — pip installable, `ares init`, `ares doctor`, launchd plist