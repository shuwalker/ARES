# ARES Architecture (Current — May 2026)

## What ARES Is

ARES is an autonomous reasoning and execution system for Jenkins Robotics.
It has a Python **brain** (cognitive loop, personality, MCP tools) and a Swift **face**
(native macOS app with cinematic avatar + engineering visualization).

The brain thinks. The face renders. They talk over WebSocket.

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
| `api.py` | 444 | FastAPI server: 8 REST endpoints + WebSocket |
| `mcp_serve.py` | 514 | MCP server: 8 tools for external AI clients |
| `__main__.py` | — | `python -m ares` entry |

### Core Modules (ares/core/)

| File | Lines | Purpose |
|------|-------|---------|
| `bus.py` | 474 | ZMQ pub/sub bus — 9 channels (brain_output, face_state, audio_raw, audio_processed, system, mcp_bridge, robot_command, robot_sensor, memory) |
| `cognitive.py` | 523 | 4-phase cognitive loop: PERCEIVE → THINK → ACT → REFLECT with guidance matrix and stop hooks |
| `personality.py` | 325 | 4-layer personality: HEXACO traits → SPECIAL traits → Expression style → Domain weights. Generates system prompts |
| `identity.py` | — | Who ARES is — values, name, backstory |
| `face_state.py` | — | FaceState enum (idle, thinking, speaking, happy, angry, neutral) + intensity mapping |
| `memory.py` | 197 | Persistent memory layer |

### Runtime (ares/runtime/)

| File | Lines | Purpose |
|------|-------|---------|
| `hermes_bridge.py` | 195 | HTTP client to Hermes agent (stub — needs v2 with ZMQ+IPC) |
| `brain_transport.py` | — | Transport abstraction for LLM calls |
| `launcher.py` | — | Process launcher for brain + face |
| `bootstrap.py` | — | First-run setup |
| `env_detector.py` | — | Environment detection (GPU, display, platform) |

### Models (ares/models/)

| File | Lines | Purpose |
|------|-------|---------|
| `system.py` | — | System models (config, state) |
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

## Swift Face (ares/reference/swift-ui/)

### Current State: POC (2D Canvas)

The current Swift code is a **proof of concept** using SwiftUI Canvas for rendering.
It works but is not CGI quality. It will be replaced with RealityKit + Metal shaders.

| File | Lines | Purpose |
|------|-------|---------|
| `ARESApp.swift` | 810 | Main app: black fire avatar, chat, immersion levels, menu bar |
| `BlackFireSystem.swift` | 67 | Canvas rendering for fire entity |
| `VoiceManager.swift` | 48 | AVFoundation mic input |
| `Package.swift` | 11 | SPM config |

### macOS App (reference/swift-ui/mac_sources/ARES-Mac/)

| File | Lines | Purpose |
|------|-------|---------|
| `ARESApp.swift` | 27 | macOS app entry |
| `FaceRenderer.swift` | 114 | Face rendering in macOS window |
| `FaceState.swift` | 70 | FaceState enum for macOS |
| `FaceWindowView.swift` | 16 | Face window container |
| `HermesBridge.swift` | 37 | HTTP bridge to brain |
| `PythonBackend.swift` | 73 | Python process management |
| `VoiceManager.swift` (shared) | 48 | Mic input |
| `MenuBarView.swift` | 62 | Menu bar presence |
| `CheckpointManager.swift` | 65 | State checkpointing |
| `ConsciousnessDaemon.swift` | 118 | Background consciousness loop |
| `CalendarBridge.swift` | 44 | Calendar integration |
| `SettingsView.swift` | 70 | Settings UI |
| `Logger.swift` | 47 | Logging |

**Total Swift LOC: ~1,891**

### What's Being Replaced

The POC Canvas renderer (`drawAnimeFire()`) is being replaced by a **RealityKit + Metal 
shader pipeline**. See [RENDERING_ARCHITECTURE.md](./RENDERING_ARCHITECTURE.md) for the 
full plan. Key changes:

- `Canvas { ctx in drawAnimeFire() }` → `MTKView` / `RealityView` with Metal shaders
- `TimelineView(.animation)` → Metal frame loop via `MTKViewDelegate`
- `Path` bezier curves → SDF raymarching in fragment shaders
- `FireParticle` CPU struct → GPU compute buffer (10K particles)
- Expression tint colors → Shader uniforms (float3 diffuseColor, float bloomIntensity)
- Single avatar style → 6 switchable styles (blackFire, anime, hologram, blob, pixelVolume, constellation)
- Engineering visualization (USDZ, glTF, STL) → RealityKit built-in

### What's Being Kept

- FaceState enum and state transition logic
- AvatarExpression → tint mapping (generalized to shader uniforms)
- AgentState intensity levels (generalized to shader parameters)
- ImmersionLevel concept (Desktop/Window/Room)
- ARESWorld state management pattern
- MenuBarExtra structure
- ChatStream + CommandBar UI pattern
- VoiceManager mic integration
- ARESMessage model

## Communication Protocols

### WebSocket (Brain ↔ Face)

The primary channel. Brain at `ws://localhost:7860/ws`, Face connects as client.

```json
// Face → Brain
{"type": "chat", "text": "status of JP01 build"}
{"type": "personality_update", "traits": {"honesty": 0.8}}
{"type": "voice_input", "audio_base64": "..."}

// Brain → Face
{"type": "face_state", "state": "thinking", "intensity": 0.85, "expression": "curious"}
{"type": "chat_response", "text": "JP01 is at phase 3..."}
{"type": "avatar_style", "style": "blackFire"}
{"type": "robot_joint", "joints": {"base": 15.2, "shoulder": 30.0}}
```

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

## Build Priority (What's Next)

1. **Swift Face v2** — RealityKit + Metal shader app (replaces Canvas POC)
2. **Hermes Bridge v2** — ZMQ+IPC connection to real Hermes agent
3. **Voice pipeline** — STT mic → brain → TTS speaker
4. **Robot control** — JP01 servo commands over bus to serial/USB
5. **Tests** — pytest suite for core, bus, cognitive loop, MCP, API
6. **Install** — pip installable, `ares init`, `ares doctor`, launchd plist