# ARES Avatar & UI Framework Research (May 2026)

## The Question

How should ARES render its face? What technology gives us the best 
combination of visual quality, state-driven animation, Apple platform 
coverage, and developer velocity?

Reference points: Project Ava (Razer), Claude Desktop, ChatGPT macOS, 
Apple Intelligence, Live2D, VRM, RealityKit.

---

## What Matthew Wants (from past sessions)

1. **3D animated avatar** — "black fire entity" aesthetic, NOT a 2D cartoon
2. **Multi-layer UI** — menu bar popover, companion window, full immersion
3. **Voice-first** — mic → STT → brain → TTS → speaker, avatar lip-syncs
4. **Always-on** — lives in the menu bar, overlay on screen like Dynamic Island
5. **Cross-platform** — Mac first, then iPhone, Watch, Vision Pro
6. **State-driven** — face responds to face_state (neutral, thinking, speaking, 
   happy, angry, idle) in real-time from the brain

---

## Framework Comparison

### Tier 1: Real Options

| Framework | 3D? | macOS | iOS | watchOS | visionOS | State Machines | Lip Sync | Dev Speed | M-Series Perf |
|-----------|-----|-------|-----|---------|----------|----------------|----------|------------|---------------|
| **RealityKit** | ✅ Full | ✅ | ✅ | ❌ | ✅ | Custom code | Custom code | Medium | Excellent |
| **SceneKit** | ✅ Full | ✅ | ✅ | ❌ | ❌ | Custom code | Custom code | Medium | Good |
| **Rive** | ❌ 2D+ | ✅ | ✅ | ✅ | ✅ | ✅ Built-in | ✅ Audio react | Fast | Excellent |
| **Live2D Cubism** | ❌ 2.5D | ✅ | ✅ | ❌ | ❌ | ✅ Built-in | ✅ MotionSync | Slow (C++ bridge) | Good |
| **Metal (custom)** | ✅ Full | ✅ | ✅ | Partial | Partial | Custom shaders | Custom | Very Slow | Direct GPU |
| **Unity embed** | ✅ Full | ✅ | ✅ | ❌ | ✅ | ✅ Animator | ✅ Lipsync | Medium | 200+ MB binary |

### Tier 2: Not Viable

| Framework | Why Not |
|-----------|---------|
| **Lottie** | No state machines, no interactivity, After Effects export only, no watchOS |
| **React Native** | No watchOS/visionOS, poor 3D performance |
| **Flutter** | No watchOS/visionOS, custom rendering means native feel is weak |
| **Electron** | 150-300MB, no iOS/Watch/Vision, what ChatGPT/Claude Desktop use (bad) |
| **Soul Machines** | Cloud-only, enterprise SaaS pricing ($$$$), not local-first |
| **Convai** | Unity plugin only, requires Unity runtime, not native Apple |
| **Inworld AI** | Backend SDK only, no avatar rendering |
| **Didimo** | Avatar creation tool, not a rendering runtime |

---

## Detailed Analysis

### 1. RealityKit (Apple's 3D Framework)

**What it is:** Apple's high-level 3D framework. Built for AR initially, 
but since visionOS and macOS 14+, works as a plain 3D renderer without AR.

**Pros:**
- Native Apple — first-class Swift API, integrates with SwiftUI via `Model3D` 
  and `RealityView`
- USDZ model support (Apple's 3D format, create in Blender/Maya)
- Built-in physics, lighting, shadows, PBR materials
- Metal-powered, runs at 120fps on M-series
- visionOS first-class citizen (this is THE framework for Vision Pro)
- Animation via `AnimationResource` — can blend between states

**Cons:**
- No watchOS (watchOS has no 3D rendering — expect 2D fallback)
- No built-in state machine for 2D animations (you write state transitions)
- No built-in lip sync — needs custom ARKit blend shape mapping
- USDZ only — no glTF without conversion (but usdz_convert exists)
- Requires 3D model assets (Blender/Maya/Motionbuilder pipeline)
- More complex to set up than Rive

**Can it do "black fire"?** YES. Metal shaders + particle emitters in 
RealityKit can do volumetric fire effects. You'd use:
- `particles` for the flame base
- Custom Metal shader for the heat distortion / glow
- `EmitterComponent` for continuously spawning particles
- `OpacityComponent` for translucency

**Verdict:** Best 3D option for Apple platforms. If we want true 3D, 
this is it. But requires designing and rigging a 3D model.

### 2. SceneKit (Apple's Older 3D Framework)

**What it is:** Pre-RealityKit 3D framework. Still maintained, simpler API.

**Pros:**
- Simpler than RealityKit for basic scenes
- Built-in particle system and physics
- Works on macOS and iOS
- Can load .scn (SceneKit), .dae (Collada), .obj files

**Cons:**
- No visionOS support
- No watchOS
- Less modern API — SwiftUI integration is via `SceneView` (works but clunky)
- Physics and rendering are limited vs RealityKit
- Apple is clearly pushing RealityKit over SceneKit

**Verdict:** Skip. RealityKit supersedes it on every metric that matters.

### 3. Rive (Our Current Choice)

**What it is:** Interactive 2D animation runtime with state machines, 
data binding, and audio reactivity. Official SwiftUI SDK.

**Pros:**
- Fastest dev velocity — design in Rive editor, export .riv, done
- State machines with inputs — drive transitions from code (`setInput("mood", "thinking")`)
- Data binding — bind numeric values (0-1 emotions) to animation properties
- Audio reactive — can sync avatar mouth to audio output
- Runs on macOS, iOS, watchOS, visionOS — literally all 4
- ~500KB runtime
- SwiftUI-native via `RiveView`
- Hot reload from editor during development

**Cons:**
- 2D only — no real 3D depth, no volumetric effects
- "Black fire entity" would need to be a stylized 2D interpretation
- Limited physics (no real particle simulation)
- Art pipeline requires Rive editor (proprietary, but free tier)
- Can't do true mesh deformation (Live2D-style mesh warps)

**Can it do "black fire"?** PARTIALLY. You'd make a stylized 2D fire 
animation with:
- Particle-like effects using Rive's state machine transitions
- Glow/opacity transitions for heat shimmer
- Multiple layered animations for depth
- It'll look good, but it's a stylistic 2D interpretation, not real 3D

**Verdict:** Ship this first. Fastest path to a working avatar. 
Upgrade to 3D later.

### 4. Live2D Cubism (The Anime Standard)

**What it is:** Industry-standard 2.5D avatar system. Used by every 
VTuber and anime game. Mesh deformation of a 2D illustration to create 
3D-like movement.

**Pros:**
- Most expressive 2D avatars possible
- Mesh warping makes 2D art feel 3D (breathing, head tilt, hair physics)
- MotionSync plugin for real-time lip sync from audio
- Proven at scale (Hololive, Nijisanji, every gacha game)
- Native Metal rendering on Apple Silicon

**Cons:**
- REQUIRES C++ SDK → ObjC → Swift bridging (documented but painful)
- Commercial license required for distributions >100K (but free for indie)
- No watchOS, no visionOS
- Proprietary editor, proprietary format (.moc3)
- Art pipeline requires Live2D Cubism Editor (paid) or outsourcing
- ~8MB SDK binary increase
- Complex setup — mesh, deformation, parameter mapping

**Can it do "black fire"?** The avatar style would need to be drawn as 
2D art first, then rigged. "Black fire entity" as a Live2D character would 
look like an anime-style dark flame person — cool but anime, not volumetric.

**Verdict:** Strong upgrade path from Rive. The C++ bridge makes it a 
Phase 2+ option. Not Phase 1.

### 5. Metal (Custom Shaders)

**What it is:** Direct GPU programming. The lowest level you can go on Apple.

**Pros:**
- Maximum control — literally anything is possible
- Best performance (no framework overhead)
- Custom shaders can do volumetric fire, raymarching, fluid sim
- Direct access to M-series GPU

**Cons:**
- MASSIVE development time — writing shader code for every effect
- No state machine, no animation system — build from scratch
- No model loading — need to write or integrate assimp/tinygltf
- Requires Metal shader language expertise
- No cross-platform rendering — need separate GL/Vulkan for other targets
- watchOS/visionOS have limited Metal support

**Verdict:** Only if we're building a game engine. Way too low-level for 
an app. RealityKit gives us Metal underneath without writing Metal.

### 6. Unity Embedded

**What it is:** Embed a Unity runtime inside a native macOS/iOS app as 
a framework.

**Pros:**
- Best 3D avatar ecosystem (Ready Player Me, VRM, Mixamo, etc.)
- Built-in Animator state machine, blend trees, IK
- Lipsync solutions: Oculus LipSync, Salsa LipSync
- Massive asset store (3D models, animations, effects)
- Works on macOS, iOS, visionOS

**Cons:**
- Binary bloat: 200-400MB added
- Memory overhead: 200MB+ at baseline
- Unity runtime fights SwiftUI for input and rendering
- Painful integration: SwiftUIHosting + UnityAppController bridging
- Build complexity (Xcode + Unity Editor pipeline)
- Long build times
- App Store reviewers sometimes flag Unity embeds
- Updates require rebuilding in Unity Editor first

**Can it do "black fire"?** Absolutely — Unity's VFX Graph + Shader Graph 
can do insane fire/particle effects. But at what cost?

**Verdict:** Overkill for a companion app. If we were building a game, 
yes. For ARES, the overhead isn't worth it.

### 7. Project Ava (Razer)

**What it is:** Razer's CES 2026 concept — an AI gaming companion that 
appears as a holographic anime-style character on your desk. Uses a 
custom display (Razer product, not software-only).

**How it works:**
- NOT a software framework — it's a hardware + software product
- Uses a dedicated vertical display (like a photo frame) that shows 
  the avatar, making it appear holographic
- The avatar rendering is proprietary (likely Unity or Unreal)
- The AI backend uses xAI/Grok for conversation
- It's a CONSUMER PRODUCT, not an SDK we can use

**What we can learn from it:**
- The "always present companion" metaphor is validated
- Holographic/overlay style is the right UX direction
- Anime-style avatars have mass appeal (it went viral)
- Voice-first + face animation = the correct interaction model

**Can we replicate it?** The visual style YES (Rive or RealityKit). 
The holographic display NO — that's hardware. But we don't need it; 
the Mac Studio IS the display.

**Verdict:** Inspirational reference, not a technology we can adopt.

---

## The Claude Desktop / ChatGPT Comparison

| App | Framework | Avatar | Always-on | Voice | 3D |
|-----|-----------|--------|-----------|-------|-----|
| **Claude Desktop** | Electron | None | No (window) | Keyboard | No |
| **ChatGPT macOS** | Electron | None | No (window) | Voice mode | No |
| **Apple Intelligence** | Swift/AppKit | Glowing orb | Yes (menu bar) | Siri voice | No |
| **Gemini Live** | Android native | Animated blobs | Overlay | Voice | No |

None of these have 3D avatars. Apple Intelligence has the closest UX to 
what we want (menu bar, always present, minimal). Our app improves on all 
of them by adding personality expression through an animated face.

---

## What We Already Have (Game Changer)

We already have a working **black fire entity** rendered in pure SwiftUI Canvas — 
800 lines of production-quality code in `ARESApp.swift`. It does:

- 3-layer anime fire (core → mid → wisps) with Bezier curve flame tongues
- Floating ember sparks
- Glowing eyes (anime villain-style vertical pupils)
- Mouth animation when speaking
- Expression tinting (8 moods shift the fire color)
- Smooth intensity transitions between states
- Immersion levels (Desktop → Window → Room)
- Menu bar always-on presence
- HTTP client talking to brain backend
- Voice input (VoiceManager with mic button)

**This is not a prototype.** This is a real app with real rendering at 60fps.
The "black fire entity" is ALREADY RENDERING in SwiftUI Canvas — no Rive, 
no Unity, no RealityKit needed for it.

## The Real Architecture: SwiftUI Canvas + Metal Shaders

We don't need to choose between Rive and RealityKit. We already have a 
procedural avatar renderer. The architecture is:

```
SwiftUI App (existing)
├── Canvas renderer (black fire entity) ← ALREADY WORKS
├── TimelineView(.animation) for 60fps ← ALREADY WORKS  
├── Expression tinting ← ALREADY WORKS
├── AgentState enum ← ALREADY WORKS
├── FaceState bridge → brain ← NEEDS WebSocket
└── Metal shaders (UPGRADE PATH for volumetric effects)
```

### What needs building (NOT replacing):

1. **WebSocket client** — swap HTTPClient for WebSocket to :7860
2. **Personality view** — sliders bound to /api/personality
3. **Status dashboard** — bus traffic, cognitive cycle display
4. **Metal shader upgrade** — replace Canvas bezier flames with GPU compute 
   shaders for true volumetric fire (Metal Performance Shaders + compute pipeline)
5. **USDZ entity model** — optional upgrade: import a 3D model into the fire
6. **Blobs** — SwiftUI Canvas + Metal can render animated blobs too

### Metal Shader Upgrade Path (Black Fire → Volumetric)

The current Canvas renderer draws bezier flame tongues on CPU. The upgrade 
to Metal replaces this with GPU compute shaders:

- **Volumetric fire**: Metal compute shader with raymarching (SDF flame)
- **Particle emitters**: `MTLComputeCommandEncoder` for 10K+ GPU particles
- **Bloom/glow**: Post-process with `MPSImageGaussianBlur`
- **Heat distortion**: Vertex shader warp on background texture

BENEFIT: Same FaceState interface, same SwiftUI window, just swap the 
rendering layer. The brain doesn't change. The app structure doesn't change. 
Only the draw call changes — from `Canvas { ctx in drawAnimeFire() }` to 
`MTKView` with Metal pipeline.

### Blobs (Animate blobs too, you said it)

SwiftUI Canvas + Metal handles blobs naturally:
- **Metaballs**: Classic marching-squares or SDF blobs, each frame on GPU
- **Liquid animation**: Spring-connected blob centers, driven by FaceState
- **Color morphing**: Same expression tinting system, just different palette
- The fire IS a blob — it's just a spiky, animated one. Smoother = blob.

We can render multiple avatar styles with the same engine:
```swift
enum AvatarStyle {
    case blackFire    // current — spiky, anime, aggressive
    case liquidBlob   // smooth metaballs, organic, flowing
    case starField    // particle swarm, cosmic
    case glitch       // digital corruption aesthetic
}
```

---

## Cost Summary

| Approach | Dev Time | Binary Size | Platforms | Visual Quality | Dev Cost |
|----------|----------|-------------|-----------|---------------|----------|
| **SwiftUI Canvas** ← WE HAVE THIS | 0 weeks | 0 | All 4 | ⭐⭐⭐ | Done |
| **+ Metal shaders** | 2-3 weeks | ~1-2MB | Mac/iOS | ⭐⭐⭐⭐⭐ | Medium |
| **+ RealityKit 3D model** | 4-6 weeks | +5-15MB | Mac/iOS/Vision | ⭐⭐⭐⭐⭐ | Medium (+ artist) |
| **Rive** (if we wanted 2D) | 1-2 weeks | +500KB | All 4 | ⭐⭐⭐ | Low |
| **Live2D** | 6-8 weeks | +8MB | Mac/iOS | ⭐⭐⭐⭐ | High (C++ bridge) |
| **Unity embed** | 4-6 weeks | +200-400MB | Mac/iOS/Vision | ⭐⭐⭐⭐⭐ | Bloated |

---

## Final Answer

**We already have it. Don't build it twice.**

The black fire entity is ALREADY rendering in SwiftUI Canvas at 60fps. 
810 lines of production Swift code. Eyes, mouth, expression tinting, 
3-layer flames, ember sparks, intensity mapping, immersion levels, 
menu bar, voice input — all built.

The upgrade path is:

1. **NOW**: Connect the existing app to the brain (WebSocket to :7860)
2. **NEXT**: Add Metal compute shaders for volumetric fire (GPU particles, 
   bloom, heat distortion) — same window, same FaceState, GPU rendering
3. **LATER**: Add RealityKit for true 3D model import (USDZ entity inside 
   the fire, blend shape animation) — same window, same FaceState
4. **BONUS**: Add blob/metaball style as an alternative avatar mode — 
   same engine, different SDF function

We don't need Rive. We don't need Unity. We don't need to start over. 
We need to wire the existing face to the brain and then upgrade the 
rendering pipeline from CPU Canvas to GPU Metal.

```
Brain publishes FaceState → WebSocket → SwiftUI App → Avatar Renderer
                                                      ├─ Canvas (NOW — black fire)
                                                      ├─ Metal compute (NEXT — volumetric)
                                                      └─ RealityKit (LATER — 3D model)
```