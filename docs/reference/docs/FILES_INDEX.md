# ARES Project Files — Current Index

Updated after Phase 0–4 Cognitive OS shipped (see
[`COGNITIVE_OS.md`](./COGNITIVE_OS.md)).

## Repository Structure

```
ARES-Autonomous-Reasoning-Execution-System/
├── ARES-Face/                                # macOS SwiftUI app (ACTIVE)
│   ├── Package.swift
│   └── ARES-Face/
│       ├── App/
│       │   ├── ARESApp.swift                # @main, WindowGroup + MenuBarExtra
│       │   └── ARESRootView.swift            # Root layout, sidebar mount, operator routing
│       ├── Models/
│       │   ├── AgentState.swift
│       │   ├── AvatarExpression.swift
│       │   ├── AvatarStyle.swift             # 6 styles
│       │   ├── FaceConfig.swift
│       │   ├── ImmersionLevel.swift
│       │   ├── ARESMessage.swift
│       │   └── CognitiveSnapshot.swift       # Codable mirror of Pydantic contract
│       ├── Networking/
│       │   └── BrainConnection.swift          # WebSocket :7860/ws + REST fallback
│       ├── Rendering/
│       │   ├── AvatarRenderer.swift           # CustomMaterial + uniform updates
│       │   ├── AvatarEntity.swift
│       │   ├── SceneSetup.swift
│       │   └── CognitiveBindings.swift        # Phase 4: snapshot → shader uniforms
│       ├── Shaders/
│       │   ├── SharedHeader.h                 # Swift ↔ Metal bridge; cognition uniforms
│       │   ├── BlackFireSurface.metal         # Consumes emissivePulse + glitchAmplitude
│       │   ├── BlackFireGeometry.metal
│       │   ├── AnimeSurface.metal / AnimeGeometry.metal
│       │   ├── HologramSurface.metal / HologramGeometry.metal
│       │   ├── BlobSurface.metal / BlobGeometry.metal
│       │   ├── PixelVolumeSurface.metal / PixelVolumeGeometry.metal
│       │   └── ConstellationSurface.metal / ConstellationGeometry.metal
│       ├── Views/
│       │   ├── AvatarSceneView.swift          # RealityView + per-frame uniform update
│       │   ├── ChatStream.swift
│       │   ├── CommandBar.swift
│       │   ├── ImmersionBar.swift             # Hosts the heartbeat pill
│       │   ├── SidebarView.swift              # 8 tabs, routed in ARESRootView
│       │   ├── DashboardPage.swift            # Tab enum
│       │   ├── MenuBarView.swift
│       │   ├── CognitiveActivityPanel.swift   # Phase 0 heartbeat
│       │   ├── MemoryInspectorView.swift      # Phase 1 inspector
│       │   └── MissionControlPanel.swift      # Phase 2 force-directed DAG
│       └── Voice/
│           └── VoiceManager.swift
│
├── ares/                                      # Python brain (ACTIVE)
│   ├── __init__.py
│   ├── __main__.py                            # python -m ares
│   ├── cli.py                                 # ares serve / mcp / doctor
│   ├── api.py                                 # FastAPI + WebSocket (REST: status,
│   │                                          # services, identity, personality, face,
│   │                                          # chat, cognitive/{start,stop,status},
│   │                                          # memory/{episodics,facts,recall,delete},
│   │                                          # idle/{run,last_report})
│   ├── mcp_serve.py                           # MCP server (8 tools)
│   ├── config.py
│   ├── daemon.py
│   ├── memory_store.py                        # Phase 1: VectorStore + Embedder protocols,
│   │                                          # MemoryStore (SQLite + episodic + semantic)
│   ├── reasoning.py
│   ├── memory.py                              # Legacy JSONL audit log
│   ├── audit.py
│   ├── sync.py
│   ├── discovery.py
│   ├── core/
│   │   ├── bus.py                             # ZMQ pub/sub
│   │   ├── cognitive.py                       # Loop + DAG (ThoughtNodeRecord,
│   │   │                                       # on_phase_change, emit_thought_node)
│   │   ├── personality.py                     # 4-layer HEXACO model
│   │   ├── identity.py
│   │   ├── face_state.py
│   │   ├── idle.py                            # Phase 3 reflexion handlers
│   │   └── memory.py
│   ├── runtime/
│   │   ├── hermes_bridge.py                   # :9876 bridge (stub; real wiring in
│   │   │                                       # sibling PR)
│   │   ├── ares_bridge_minimal.py             # Reference: hermes -z subprocess pattern
│   │   ├── brain_transport.py
│   │   ├── session_store.py                   # Phase 1: volatile turn deque
│   │   ├── launcher.py                        # find_hermes() / hermes_status()
│   │   ├── bootstrap.py
│   │   └── env_detector.py
│   ├── models/
│   │   ├── system.py
│   │   ├── cognitive.py                       # CognitiveSnapshot Pydantic contract
│   │   ├── engineering.py
│   │   └── project.py
│   ├── skills/
│   │   ├── cognitive/                         # Perception, voice, avatar, VTS
│   │   └── physical/
│   ├── embodiment/
│   ├── llm/                                   # cloud + local routers (not on chat path)
│   ├── tasks/
│   ├── tools/
│   ├── workflows/
│   └── reference/                              # Historical / deprecated
│       ├── swift-ui/                           # Old Canvas POC (do not extend)
│       │   ├── ARESApp.swift                   # 810-line monolithic POC
│       │   ├── BlackFireSystem.swift           # Canvas fire renderer (POC)
│       │   ├── VoiceManager.swift
│       │   ├── VISION.md
│       │   ├── PLAN.md
│       │   └── mac_sources/                    # macOS-specific build
│       ├── docs/                                # You are here
│       ├── lilith-ai/                          # Reference: personality system
│       ├── voicellm/                           # Reference: voice pipeline
│       └── deprecated-agent/                   # Reference: old orchestrator
│
├── tests/
│   ├── __init__.py
│   ├── integration/
│   │   ├── conftest.py                        # Service probes; auto-skip when offline
│   │   └── test_services.py                   # 27 tests (auto-skipped without services)
│   └── unit/                                   # 46 passing
│       ├── conftest.py                        # Auto-marks `unit`
│       ├── README.md                          # Priority list for future tests
│       ├── models/
│       │   └── test_cognitive_snapshot.py     # 4
│       ├── runtime/
│       │   ├── test_cognitive_loop_hook.py    # 4
│       │   ├── test_session_store.py          # 5
│       │   └── test_thought_dag.py            # 5
│       ├── test_api_cognitive_status.py       # 2
│       ├── test_api_memory.py                 # 4
│       ├── test_memory_store.py               # 12
│       └── test_idle_reflexion.py             # 10
│
├── benchmarks/                                 # bench_quick.py / bench_accurate.py
├── .github/workflows/tests.yml                 # CI: unit on Py 3.11+3.12, ruff + black
├── pyproject.toml                              # pytest + coverage config
├── install.sh
├── com.ares.daemon.plist
├── build_app.sh
└── README.md
```

## Key Documents

| Document | Purpose |
|----------|---------|
| [`ARCHITECTURE.md`](./ARCHITECTURE.md) | Current system architecture, communication protocols, endpoints |
| [`COGNITIVE_OS.md`](./COGNITIVE_OS.md) | Single-source reference for Phase 0–4 (snapshot, memory, DAG, idle, bindings) |
| [`RENDERING_ARCHITECTURE.md`](./RENDERING_ARCHITECTURE.md) | RealityKit + Metal pipeline; cognition-driven uniforms |
| [`BUILD_SPEC_FACE_APP.md`](./BUILD_SPEC_FACE_APP.md) | Swift face app build spec (as built + cognitive instrumentation extensions) |
| [`AI_AGENT_HANDOFF.md`](./AI_AGENT_HANDOFF.md) | Handoff guide for agents picking up next work |
| [`ARES_POSITIONING_BRIEF.md`](./ARES_POSITIONING_BRIEF.md) | Positioning |
| [`COMPETITIVE_ANALYSIS_2026.md`](./COMPETITIVE_ANALYSIS_2026.md) | Competitor landscape |
| [`ARCHITECTURE_ANALYSIS.md`](./ARCHITECTURE_ANALYSIS.md) | Comparative analysis of 8 agent systems |
| [`UI_FRAMEWORK_DECISION.md`](./UI_FRAMEWORK_DECISION.md) | Why RealityKit + Metal |
| [`AVATAR_FRAMEWORK_RESEARCH.md`](./AVATAR_FRAMEWORK_RESEARCH.md) | Earlier avatar research (historical) |

## What's Built vs What's Next

### Built ✅

1. Python brain core (personality, identity, face state, cognitive loop with DAG + observer)
2. Tiered memory (`MemoryStore` + `VectorStore` + `Embedder` protocols + SQLite)
3. Idle reflexion (consolidate, dedupe, surface open questions)
4. FastAPI server + WebSocket with `cognitive_snapshot` push
5. MCP server with 8 tools
6. ARES-Face SwiftUI app — 6 RealityKit/Metal styles, heartbeat pill, Memory Inspector, Mission Control DAG, cognition-driven shader uniforms
7. Unit test scaffold + GitHub Actions CI (Py 3.11 + 3.12)
8. 46 unit tests, all passing

### Next 🔨

1. Hermes bridge wiring (`/api/chat` → bridge → real LLM) — sibling PR
2. Concrete `VectorStore` (sqlite-vss / lancedb / chromadb)
3. Voice pipeline (STT → brain → TTS)
4. Operator-tab build-out (`.models`, `.skills`, `.cron`, `.analytics`)
5. DAG replay scrubber UI
6. Robot control (JP01 over bus)
7. pip-installable distribution + launchd plist
