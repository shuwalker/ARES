# ARES Project Files — Current Index (May 2026)

## Repository Structure

```
ARES-Autonomous-Reasoning-Execution-System/
├── ares/                              # Python brain (active development)
│   ├── __init__.py
│   ├── __main__.py                    # python -m ares entry
│   ├── cli.py                         # CLI (ares serve, ares mcp, ares doctor)
│   ├── api.py                         # FastAPI server + WebSocket
│   ├── mcp_serve.py                   # MCP server (8 tools)
│   ├── config.py                      # Configuration
│   ├── daemon.py                      # Background daemon
│   ├── reasoning.py                   # Chain-of-thought reasoning
│   ├── memory.py                      # Memory management
│   ├── audit.py                       # Audit logging
│   ├── sync.py                        # Data sync
│   ├── discovery.py                   # Service discovery
│   ├── core/                          # Core modules
│   │   ├── bus.py                     # ZMQ pub/sub (9 channels)
│   │   ├── cognitive.py              # 4-phase cognitive loop
│   │   ├── personality.py             # 4-layer personality system
│   │   ├── identity.py                # ARES identity
│   │   ├── face_state.py              # Face state machine
│   │   └── memory.py                  # Persistent memory
│   ├── runtime/                        # Runtime subsystems
│   │   ├── hermes_bridge.py            # Bridge to Hermes (stub)
│   │   ├── brain_transport.py          # LLM transport
│   │   ├── launcher.py                # Process launcher
│   │   ├── bootstrap.py               # First-run setup
│   │   └── env_detector.py            # Environment detection
│   ├── models/                         # Data models
│   │   ├── system.py
│   │   ├── engineering.py             # CAD/sim/robot models
│   │   └── project.py
│   ├── skills/                         # Skill modules
│   │   ├── cognitive/                  # Perception, VTS, STT/TTS
│   │   └── physical/                   # Robot, desktop
│   ├── embodiment/                     # Embodiment interfaces
│   │   ├── desktop/
│   │   └── robot/
│   ├── llm/                            # LLM providers
│   │   ├── router.py                   # Provider routing
│   │   ├── cloud.py                    # Cloud (OpenAI, Anthropic)
│   │   └── local.py                    # Local (LM Studio)
│   ├── tasks/                           # Task management
│   │   ├── executor.py
│   │   └── queue.py
│   ├── tools/                           # Tool integrations
│   │   ├── registry.py
│   │   └── n8n.py
│   └── workflows/                      # Workflow automations
│       └── youtube.py
├── ares/reference/                      # Reference code (not active)
│   ├── swift-ui/                        # POC Swift app (Canvas renderer)
│   │   ├── ARESApp.swift               # 810 LOC — main app + fire
│   │   ├── BlackFireSystem.swift       # Canvas fire renderer (POC)
│   │   ├── VoiceManager.swift          # AVFoundation mic
│   │   ├── Package.swift
│   │   └── mac_sources/                # macOS-specific build (12 files)
│   ├── docs/                            # Architecture and research
│   │   ├── ARCHITECTURE.md             # ← YOU ARE HERE (current architecture)
│   │   ├── RENDERING_ARCHITECTURE.md   # Vision Engine full technical plan
│   │   ├── RESEARCH_HISTORY.md          # Decisions tried and conclusions
│   │   ├── FILES_INDEX.md              # ← YOU ARE HERE (this file)
│   │   ├── AVATAR_FRAMEWORK_RESEARCH.md # Earlier avatar research (historical)
│   │   ├── UI_FRAMEWORK_DECISION.md    # Earlier UI comparison (historical)
│   │   ├── RESEARCH_SUMMARY.md         # Research summary
│   │   ├── RESEARCH_SOURCES.md         # Research source links
│   │   ├── RESEARCH_INDEX.md           # Research index
│   │   ├── AREAS_POSITIONING_BRIEF.md  # ARES positioning document
│   │   ├── COMPETITIVE_ANALYSIS_2026.md # Competitive landscape
│   │   ├── RESTRUCTURING_COMPLETE.md   # Repo restructuring notes
│   │   ├── AI_AGENT_HANDOFF.md         # Agent handoff guide
│   │   └── ARCHITECTURE_ANALYSIS.md    # Architecture analysis (historical)
│   ├── lilith-ai/                       # Reference: personality system
│   ├── voicellm/                        # Reference: voice pipeline
│   └── deprecated-agent/                # Reference: old orchestrator
├── pyproject.toml                       # Python project config
├── install.sh                           # Install script
├── com.ares.daemon.plist               # launchd plist
└── README.md
```

## Code Statistics

| Component | Language | LOC | Status |
|-----------|----------|-----|--------|
| Python brain | Python | ~8,293 | Active development |
| Swift face (POC) | Swift | ~1,891 | Reference only (replacing) |
| **Total** | | **~10,184** | |

## Key Documents

| Document | Purpose | Audience |
|----------|---------|----------|
| `ARCHITECTURE.md` | Current system architecture | Anyone building ARES |
| `RENDERING_ARCHITECTURE.md` | Vision Engine technical plan | Anyone building the Swift face |
| `RESEARCH_HISTORY.md` | Decisions tried and conclusions | Anyone questioning why we chose X |
| `FILES_INDEX.md` | This file — project file map | Anyone navigating the repo |
| `AVATAR_FRAMEWORK_RESEARCH.md` | Earlier avatar research (historical) | Historical reference only |
| `UI_FRAMEWORK_DECISION.md` | Earlier UI comparison (historical) | Historical reference only |

## What's Built vs What's Next

### Built ✅
1. Python brain core (personality, identity, face state, cognitive loop, ZMQ bus)
2. FastAPI server with 8 REST endpoints + WebSocket
3. MCP server with 8 tools
4. CLI (`ares serve`, `ares mcp`, `ares doctor`)
5. Swift POC app with Canvas fire avatar (reference only)

### Next 🔨
1. Swift Face v2 — RealityKit + Metal shader app (replaces POC)
2. Hermes bridge v2 — ZMQ+IPC connection to real Hermes agent
3. Voice pipeline — STT mic → brain → TTS speaker
4. Robot control — JP01 servo commands over bus
5. Tests — pytest suite
6. Install — pip installable, launchd plist