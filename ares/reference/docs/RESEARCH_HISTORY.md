# ARES Research History — Decisions Tried and Conclusions

This document tracks what we researched, what we tried, what we concluded, and why.
It exists so we don't re-litigate decisions without new information.

---

## 1. AI Companion Avatar Rendering (May 2026)

### Question
How should ARES render its face? What framework gives CGI movie quality with
switchable styles (anime, realistic, holographic, volumetric) AND supports
engineering model visualization (CAD, FEA, robot joints)?

### Options Considered

| Option | What | Verdict | Why |
|--------|------|---------|-----|
| **SwiftUI Canvas** | 2D bezier curves, CPU-drawn | ❌ POC only | Not CGI quality. Flat 2D. No 3D. No engineering models. Current code is a prototype, not the product. |
| **Rive** | 2D state-driven animation SDK | ❌ Rejected | 2D only. Can't render volumetric fire. Can't load USDZ models. Pre-baked states, not procedural. Would need replacing. |
| **Pure Metal (MTKView)** | Custom GPU rendering from scratch | ❌ Rejected | Would require building scene graph, model loader, physics, camera, lighting, PBR, hit testing, USDZ parser from scratch. 6-12 months before rendering a single engineering model. |
| **Unity embed** | Unity as SwiftUI view | ❌ Rejected | 200-400MB binary bloat. Fights SwiftUI for memory/events. Overkill for what we need. Licensing complexity. |
| **Live2D** | Anime mesh deformation SDK | ❌ Rejected | C++ bridge layer needed. Mac/iOS only (no watchOS/visionOS). Cannot render engineering models. Single style (anime). |
| **Three.js / WebGL** | Browser-based 3D | ❌ Rejected | Web-only, not native Apple. No access to Metal GPU. No AVFoundation for mic. No SwiftUI integration. |
| **RealityKit + Metal CustomMaterials** | Apple's scene framework + custom GPU shaders | ✅ CHOSEN | See below. |

### Decision: RealityKit + Custom Material

**Chosen: RealityKit + Custom Material**

RealityKit provides:
- ✅ USDZ/glTF/STL model loading (built-in)
- ✅ Physics simulation (built-in)
- ✅ Camera orbit/zoom/pan gestures (built-in)
- ✅ PBR lighting and IBL (built-in)
- ✅ Articulated bodies for robot joints (built-in)
- ✅ Hit testing and selection (built-in)
- ✅ Cross-section/cutaway views (built-in)
- ✅ Annotations and labels (built-in)
- ✅ visionOS spatial computing (first-class)
- ✅ Custom Material API for our Metal shaders

Custom Material gives us:
- ✅ Full GPU shader control for fire/anime/hologram/blob/etc.
- ✅ Geometry modifier (vertex displacement per frame)
- ✅ Surface shader (fragment coloring per pixel)
- ✅ Style switching = shader function swap at runtime
- ✅ Same FaceState interface drives all styles

### Why Not Pure Metal

Pure Metal (MTKView from scratch) would give maximum performance and control,
but requires building an entire scene management system before we can load a
single engineering model. The RealityKit overhead is minimal (~1-2ms per frame)
and we get physics, model loading, camera, and visionOS for free.

### Style Switching Architecture

Six styles, each a Metal shader pair (geometry modifier + surface shader):

| Style | Shader | Look |
|-------|--------|------|
| blackFire | Raymarched SDF, black body radiation | Volumetric dark fire |
| anime | Cel-shaded same volume, hard edges | Anime character face |
| hologram | Scan lines, chromatic aberration, flicker | Sci-fi projection |
| blob | Metaball smooth merge, organic | Liquid organism |
| pixelVolume | Voxelized density, blocky | Minecraft-meets-fire |
| constellation | Point cloud + triangulation | Star map face |

Adding new styles = writing one `.metal` file. No app changes.

### Engineering Visualization

Same scene, same renderer. Avatar face and JP01 robot arm coexist:

```swift
scene.addChild(avatarEntity)    // CustomMaterial shader
scene.addChild(robotModel)       // RealityKit PBR
```

Custom materials for FEA stress maps, heat maps, fluid dynamics overlays.
Same shader pipeline, different fragment function.

### Reference Files
- `RENDERING_ARCHITECTURE.md` — Full technical detail, file structure, shader examples
- `AVATAR_FRAMEWORK_RESEARCH.md` — Earlier research comparing all options (historical)
- `UI_FRAMEWORK_DECISION.md` — Earlier UI framework comparison (historical)

---

## 2. Brain-Face Communication (May 2026)

### Question
How should the Python brain and Swift face communicate?

### Options Considered

| Option | Verdict | Why |
|--------|---------|-----|
| HTTP REST only | ❌ Rejected | No streaming, no real-time state updates, polling overhead |
| gRPC | ❌ Rejected | Complex proto definitions, overkill for two processes on same machine |
| SSH tunnel | ❌ Rejected | Wrong layer, adds complexity for no benefit |
| WebSocket + REST | ✅ CHOSEN | Real-time bidirectional for state/streaming, REST for config |

### Decision: FastAPI with REST + WebSocket

- REST endpoints for config, personality, status queries
- WebSocket for real-time face_state, chat streaming, robot sensor data
- Brain at `localhost:7860`, Face connects as WebSocket client
- ZMQ for internal brain module communication (not exposed to Face)

---

## 3. Personality System Architecture (May 2026)

### Question
How should ARES personality work?

### Decision: 4-Layer System

1. **HEXACO traits** — 6 base traits (Honesty, Emotionality, eXtraversion, Agreeableness, Conscientiousness, Openness). Slow-changing, defines core personality.

2. **SPECIAL traits** — 5 derived traits (Curiosity, Humor, Loyalty, Bluntness, Empathy). Medium-changing, defines interpersonal style.

3. **Expression style** — 3 parameters (Verbosity, Formality, Warmth). Fast-changing, defines communication format.

4. **Domain weights** — Per-topic expertise emphasis (Robotics, Video, Hardware, etc.).

Each layer feeds into system prompt generation. The Face exposes sliders for
all of these via `/api/personality`.

---

## 4. Cognitive Loop Design (May 2026)

### Question
How should ARES think?

### Decision: PERCEIVE → THINK → ACT → REFLECT

- **PERCEIVE**: Receive input (text, voice, sensor, system event)
- **THINK**: Route to LLM with personality-injected system prompt
- **ACT**: Execute response (send message, move robot, call tool)
- **REFLECT**: Evaluate action quality, update memory, adjust state

Guidance matrix maps input type to action priority. Stop hooks prevent
infinite loops. Each phase publishes to ZMQ bus.

---

## 5. Hermes Integration (May 2026)

### Question
How does ARES brain connect to the existing Hermes agent?

### Status: Stub (needs v2)

Current `hermes_bridge.py` is HTTP-only. Needs upgrade to:
- ZMQ subscriber on `brain_output` channel
- IPC bridge for tool calls
- Bidirectional message routing

Hermes runs on Mac Studio at `:9520` (MCP). ARES brain subscribes to
Hermes events and routes tool calls through MCP bridge.

---

## 6. Voice Pipeline (May 2026)

### Question
How does voice input/output work?

### Status: Reference code exists, not integrated

Reference implementations in `ares/reference/voicellm/`:
- STT: Whisper (continuous + two-pass)
- VAD: Voice activity detection
- TTS: Kokoro
- AEC: Acoustic echo cancellation
- Orchestrator: Routes STT → brain → TTS

The Swift Face has `VoiceManager.swift` (AVFoundation mic input).
Needs integration: Face captures audio → WebSocket → brain STT → cognitive loop → TTS → Face plays.

---

## Template for New Entries

```markdown
## N. Title (Date)

### Question
What decision needed making?

### Options Considered
| Option | Verdict | Why |

### Decision
What was chosen and why.

### Status
Current state (implemented/planned/needs revision).

### Reference Files
Links to relevant docs/code.
```