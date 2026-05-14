# ARES Rendering Engine Architecture

## The Real Requirement

This isn't just an avatar renderer. It's an **engineering visualization engine** that
also renders an AI companion face. It needs to:

1. Show a cinematic AI avatar (fire, anime, hologram, blob, etc.)
2. Load and render CAD/engineering models (USDZ, glTF, STL)
3. Display physics simulations (FEA stress maps, fluid dynamics)
4. Show robot joint states in real-time (JP01 arm visualization)
5. All in the same app, same scene, at the same time if needed

The face can be IN the scene with the robot. The robot can visualize
while the face thinks. Same engine.

## Hardware We're Optimizing For

```
Mac Studio (M1 Max)
├── GPU: 24-core Apple GPU (Metal 4)
├── RAM: 32 GB unified memory (CPU + GPU share)
├── Display: 4K @ 60Hz (LG UltraFine)
├── Xcode 26.5, Swift 6.3.2
└── Available frameworks: Metal, MetalKit, MPS, MPSGraph,
    RealityKit, SceneKit, ARKit (all present)
```

M1 Max has:
- 24 GPU cores → enough for raymarching + particle sim + model rendering simultaneously
- 32 GB unified memory → GPU can access full model data without copying
- Metal 4 support → latest shader features, mesh shaders, ray tracing API
- 400 GB/s memory bandwidth → no bottleneck feeding the GPU

## Why RealityKit + Custom Metal (Not Pure Metal)

| Need | Pure Metal | RealityKit + Metal |
|------|-----------|-------------------|
| Avatar fire shader | ✅ Custom | ✅ CustomMaterial |
| Load USDZ/glTF models | 🔴 Build from scratch | ✅ Built-in |
| Physics simulation | 🔴 Bullet/PhysX integration | ✅ Built-in physics |
| Robot arm articulation | 🔴 Custom IK solver | ✅ ArticulatedBodyComponent |
| Camera orbit/zoom | 🔴 Custom camera controller | ✅ Built-in gestures |
| Lighting/PBR | 🔴 Custom shader | ✅ Built-in IBL + PBR |
| Hit testing / selection | 🔴 Custom raycaster | ✅ Built-in |
| Annotations / labels | 🔴 Custom | ✅ HasAttachment + Text |
| Cross-section views | 🔴 Custom clipping | ✅ Built-in |
| visionOS spatial | 🔴 Custom compositor | ✅ First-class |
| Scene graph management | 🔴 Custom | ✅ Entity-Component |
| Engineering annotations | 🔴 Custom | ✅ USDZ metadata |
| Model import (STL/OBJ/glTF) | 🔴 assimps or similar | ✅ Built-in converters |
| Avatar rendering | ✅ Full control | ✅ CustomMaterial shader |
| Performance | ⭐⭐⭐⭐⭐ Maximum | ⭐⭐⭐⭐ Slight overhead |

**RealityKit gives us the engineering visualization for free.** Custom Metal shaders
give us the cinematic avatar. Together they cover everything.

**Pure Metal means building a scene graph, model loader, physics engine, camera
controller, gesture recognizer, USDZ parser, and PBR lighting system from scratch.**
That's 6-12 months of work before we render a single engineering model.

**RealityKit + CustomMaterial means we import a USDZ, drop it in a scene, and
our avatar shader runs alongside it on day one.**

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  ARES App (SwiftUI)                                        │
│  ├── ARESWorld (state management, WebSocket to brain)      │
│  ├── ContentView                                            │
│  │   ├── MenuBarExtra (always on)                          │
│  │   ├── MainWindow                                        │
│  │   │   ├── AresSceneView (RealityKit)                    │
│  │   │   │   ┌─────────────────────────────────────┐       │
│  │   │   │   │  RealityKit Scene                    │       │
│  │   │   │   │                                     │       │
│  │   │   │   │  ┌──────────┐   ┌───────────────┐  │       │
│  │   │   │   │  │ Avatar   │   │ Engineering   │  │       │
│  │   │   │   │  │ Entity   │   │ Models        │  │       │
│  │   │   │   │  │ (Custom  │   │ (PBR/USDZ/   │  │       │
│  │   │   │   │  │ Material)│   │  glTF/STL)    │  │       │
│  │   │   │   │  └──────────┘   └───────────────┘  │       │
│  │   │   │   │         ↑ same scene, same camera   │       │
│  │   │   │   │                                     │       │
│  │   │   │   │  Physics visualization overlay      │       │
│  │   │   │   │  Robot joint state (real-time)      │       │
│  │   │   │   │  Stress/heat maps on models        │       │
│  │   │   │   └─────────────────────────────────────┘       │
│  │   │   │   ← CustomMaterial for avatar shader          │
│  │   │   │   ← Built-in PBR for engineering models      │
│  │   │   ├── PersonalityPanel (sliders)                   │
│  │   │   ├── StatusPanel (bus, cycle, robot)             │
│  │   │   └── CommandBar (input + mic)                    │
│  │   └── ImmersiveSpace (visionOS full room)             │
│  ├── WebSocketClient (connects to :7860)                  │
│  └── VoiceManager (AVFoundation)                          │
└─────────────────────────────────────────────────────────────┘
```

## How Custom Material Works in RealityKit

RealityKit's `CustomMaterial` lets us write Metal shaders that run inside
the RealityKit render pipeline. We get the scene graph, physics, model loading
for free, and our avatar gets full GPU shader control.

```swift
// Avatar entity with custom shader material
let avatarEntity = ModelEntity(mesh: .generateSphere(radius: 0.15))

let fireMaterial = CustomMaterial(
    geometryModifier: CustomMaterial.GeometryModifier(
        named: "fire_geometry",      // Metal shader function
        in: metalLibrary
    ),
    surfaceShading: CustomMaterial.SurfaceShading(
        named: "fire_surface",       // Metal shader function
        in: metalLibrary
    ),
    EmmissiveColor(0, 0, 0),        // self-illumination
    faceCulling: .none,               // double-sided fire
    blendMode: .transparent           // alpha blending
)

avatarEntity.model?.materials = [fireMaterial]

// Style switching = swap shader functions
func setAvatarStyle(_ style: AvatarStyle) {
    let shaderName = switch style {
    case .blackFire:    "blackfire_surface"
    case .anime:        "anime_surface"
    case .hologram:     "hologram_surface"
    case .blob:         "blob_surface"
    case .pixelVolume:  "voxel_surface"
    case .constellation: "constellation_surface"
    }
    fireMaterial.surfaceShading = CustomMaterial.SurfaceShading(
        named: shaderName, in: metalLibrary
    )
}
```

## Engineering Visualization (Why RealityKit Matters)

```swift
// Load a JP01 robot arm model
let robotModel = try! Entity.loadModel(named: "JP01_arm.usdz")
scene.addChild(robotModel)

// Animate joints from real sensor data
for (name, angle) in jointAngles {
    let joint = robotModel.findEntity(named: name)
    joint?.setOrientation(Simdf(angle: angle, axis: [0,0,1]),
                          relativeTo: joint!.parent!)
}

// Stress visualization — map FEA results to vertex colors
let stressMaterial = CustomMaterial(
    surfaceShading: CustomMaterial.SurfaceShading(
        named: "stress_heatmap",  // blue→green→yellow→red
        in: metalLibrary
    ),
    ...

// Cutaway view
robotModel.components[ClippingPlaneComponent.self] = ClippingPlaneComponent(
    normal: [0, 1, 0], offset: 0
)

// The avatar face can be IN the same scene
// ARES floating beside the robot it's controlling
scene.addChild(avatarEntity)
scene.addChild(robotModel)
```

### What This Enables

| Mode | What You See | How |
|------|-------------|-----|
| **Companion** | Avatar face floating on desktop | Avatar entity + custom shader |
| **Robot control** | 3D JP01 model with live joint positions | USDZ model + real-time articulation |
| **Physics sim** | FEA stress map on a bracket | Custom material (heatmap) on mesh |
| **CAD review** | Full model with orbit/zoom/section | Built-in camera gestures |
| **Mixed** | Avatar face NEXT TO robot model | Both in same scene |
| **Immersive** | Avatar + robot in room-scale (Vision Pro) | ImmersiveSpace |

## Metal Shader Pipeline (Avatar Styles)

Each style is two Metal shader functions: a **geometry modifier** (moves vertices)
and a **surface shader** (colors pixels). RealityKit calls these per frame.

### Black Fire (Volumetric Realistic)

```metal
// geometry modifier: displace sphere surface with noise-based flames
[[vertex]] float3 fire_geometry(float3 position, float3 normal,
                                 float2 uv, float4 color,
                                 float time, float intensity) {
    float3 p = position;
    float noise = fbm(p * 3.0 + float3(0, time * 2.0, 0));
    float flame = noise * intensity * 0.3;
    p += normal * flame;
    p.y += flame * 1.5; // stretch upward
    return p;
}

// surface shader: black body radiation coloring
[[fragment]] float4 fire_surface(float3 position, float3 normal,
                                  float2 uv, float4 color,
                                  float intensity, float time) {
    float density = sdFlame(position, time); // SDF
    float3 col = blackBodyRadiation(density * intensity);
    col += bloom(col, 0.5); // hot glow
    float alpha = smoothstep(0.0, 0.1, density * intensity);
    return float4(col, alpha);
}
```

### Anime (Cel-Shaded)

Same SDF volume input, different visual output:
- Quantize lighting to 3-4 flat bands
- Hard outline pass (Sobel edge detection)
- Specular as hard dots, not smooth
- Speed lines during transitions

### Hologram (Sci-Fi)

- Scan lines (horizontal, offset per line)
- Chromatic aberration (RGB channels split 1-2px)
- Random frame dropout (1-2 frames black)
- Transparency pulse (0.4-0.8 alpha sine)
- Wireframe structure visible through semi-transparent surface

### Blob (Metaball)

- SDF smooth minimum for merging 3-5 blob centers
- Spring-connected, driven by FaceState
- Fresnel rim lighting, surface caustics
- Internal structure visible through transparency

### Pixel Volume (Voxel)

- Density field quantized to 8×8 or 16×16 blocks
- Blocks pop in/out with state
- 3D rotation shows depth
- Each voxel colored by temperature/density

### Constellation (Star Map)

- Point cloud of glowing dots
- Delaunay triangulation lines connecting nearby points
- Points drift when idle, cluster when thinking
- Face emerges from connectivity patterns

## Performance Budget (M1 Max, 24 GPU Cores)

| Component | Time | Notes |
|-----------|------|-------|
| Avatar geometry modifier | 0.2ms | Sphere displacement |
| Avatar surface shader | 0.5ms | Style-dependent raymarching |
| Engineering model PBR | 1-2ms | Depends on polygon count |
| Physics simulation | 0.5ms | RealityKit built-in |
| Post-processing (bloom) | 0.3ms | MPS Gaussian blur |
| **Total frame** | **2.5-3ms** | **330fps** (cap at 120) |
| GPU memory | 50-200MB | Models + shader buffers |
| CPU overhead | Minimal | Scene graph onRealityKit |

M1 Max can do all of this simultaneously without breaking a sweat.

## File Structure

```
ARES-App/
├── Package.swift                    # SPM, targets macOS 15+, iOS 18+, visionOS 2+
├── ARES-App.xcodeproj              # Xcode project (generated by SPM or manual)
├── Sources/
│   ├── App/
│   │   ├── ARESApp.swift            # @main, WindowGroup + MenuBarExtra
│   │   └── AppDelegate.swift        # macOS-specific: dock, activation
│   ├── Core/
│   │   ├── ARESWorld.swift          # @Observable state machine (FaceState, mode)
│   │   ├── WebSocketClient.swift    # Async connect to :7860, streaming
│   │   ├── FaceStateModels.swift    # Codable matching Python brain models
│   │   └── PersonalityClient.swift  # GET/POST /api/personality
│   ├── Rendering/
│   │   ├── AresSceneView.swift      # RealityKit RealityView wrapper
│   │   ├── AresScene.swift          # Scene setup, lighting, camera
│   │   ├── AvatarEntity.swift        # Avatar model entity + style switching
│   │   ├── AvatarStyle.swift         # Enum of all styles
│   │   ├── EngineeringModel.swift    # Load USDZ/glTF/STL, joint control
│   │   └── StressVisualization.swift # Custom material for FEA/heat maps
│   ├── Shaders/
│   │   ├── Common.metal             # Shared noise, SDF, utility functions
│   │   ├── BlackFire.metal           # Realistic volumetric fire
│   │   ├── Anime.metal               # Cel-shaded anime style
│   │   ├── Hologram.metal            # Sci-fi projection style
│   │   ├── Blob.metal               # Metaball organism style
│   │   ├── PixelVolume.metal        # Voxel density style
│   │   ├── Constellation.metal       # Star map style
│   │   └── StressHeatmap.metal       # Engineering: FEA stress colors
│   ├── Views/
│   │   ├── ChatStream.swift          # Message list
│   │   ├── CommandBar.swift          # Input + mic
│   │   ├── PersonalityPanel.swift    # HEXACO/SPECIAL sliders
│   │   ├── StatusDashboard.swift      # Bus, cycle, robot joints
│   │   └── RobotJointView.swift      # JP01 arm visualization
│   └── Voice/
│       └── VoiceManager.swift        # AVFoundation mic/speaker
├── Resources/
│   ├── Models/
│   │   └── JP01_arm.usdz            # Robot arm model (placeholder)
│   └── Shaders/
│       └── (compiled .metallib)
└── Tests/
    └── AresRenderingTests.swift      # Shader validation, scene loading
```

## What This ISN'T

- It's NOT a game engine. No scripting, no ECS beyond RealityKit's built-in.
- It's NOT Unity. No 200MB embed, no separate editor, no C#.
- It's NOT a web viewer. Native Apple platforms only (macOS, iOS, visionOS, watchOS fallback).
- It's NOT Three.js. No browser, no WebGL, no DOM overhead.

## What This IS

**ARES Vision Engine** — a native Apple rendering system that's:
- An AI companion face (cinematic, style-switchable)
- An engineering model viewer (USDZ, glTF, STL)
- A robot teleoperator (JP01 joint control in 3D)
- A physics simulation display (FEA, CFD, thermal)
- All in one scene, one app, one renderer

Trademark feature: **The Ares Face.** No other AI has this.

---

## Cognition-Driven Shader Uniforms (Phase 4)

The renderer now reacts to ARES's cognitive state, not just face-state.
The avatar's body language reflects what the brain is doing: confidence
brightens the core, errors trigger pixel-glitch, reasoning depth jitters
vertices, urgency modulates noise scale.

This is wired declaratively so adding a new metric is a **one-line
change** in `Rendering/CognitiveBindings.swift`. Shaders that don't
reference new uniforms keep working unchanged.

### Schema

`Shaders/SharedHeader.h` — `SurfaceCustomUniforms` grew four trailing
fields. Field order matches `AvatarRenderer.swift`'s Swift mirror
(struct memory layout is the contract; ordering must stay aligned).

```objc
typedef struct {
    float intensity;        // 0..1 — existing
    float expression;       // 0..7 — existing
    float isSpeaking;       // 0|1 — existing
    float time;             // seconds — existing
    // Cognition uniforms (Phase 4) — bound from CognitiveSnapshot:
    float noiseScale;       // 0..1, driven by urgency
    float emissivePulse;    // 0..1, confidence + urgency wobble
    float vertexJitter;     // 0..1, reasoning depth / 10
    float glitchAmplitude;  // 0..1, error count / 5 (capped)
} SurfaceCustomUniforms;
```

### Binding table

`Rendering/CognitiveBindings.swift` — pure function from snapshot to
uniform values:

```swift
enum CognitiveBindings {
    static func evaluate(_ snapshot: CognitiveSnapshot, time: Float)
        -> CognitiveUniformValues
}
```

Current bindings:

| Snapshot field | Uniform | Mapping |
|---|---|---|
| `loop.urgency` | `noiseScale` | low=0.32, medium=0.6, high=1.0 |
| `thought.confidence` + urgency wobble | `emissivePulse` | base + `urgency * sin(time*4)` |
| `thought.depth` | `vertexJitter` | min(depth, 10) / 10 |
| `errors.count` | `glitchAmplitude` | min(count / 5, 1) |

All values clamped to `[0..1]` in the binding layer so shaders never
have to guard.

### Per-frame application

`AvatarSceneView.swift::updateAvatarUniforms()` calls
`CognitiveBindings.evaluate(brain.cognitive, time:)` each frame and
forwards the result alongside the existing `intensity / expression /
isSpeaking / time` block to `AvatarRenderer.updateSurfaceUniforms(...)`.

### Adding a new binding

1. Add a field to `CognitiveUniformValues` (Swift).
2. Implement it in `CognitiveBindings.evaluate` — one line each.
3. Add a matching field in `SharedHeader.h` and the
   `SurfaceCustomUniforms` mirror in `AvatarRenderer.swift` (same
   order in both).
4. Reference the new uniform in any `.metal` shader that needs it.

Done. Five steps, no shader rewrites for unrelated metrics.

### Reference: shader usage in `BlackFireSurface.metal`

```metal
// Confidence brightens the core; clamped on the Swift side so no
// per-shader guarding is needed.
color *= (0.85 + 0.3 * customParams.emissivePulse);

// Glitch — pixel-jump that scales with the error count.
if (customParams.glitchAmplitude > 0.0) {
    float glitch = hash21(uv * 80.0 + float2(time * 17.0)) - 0.5;
    color += float3(glitch) * customParams.glitchAmplitude * 0.4;
}
```

The other five styles ignore the new fields until similarly updated.
See [`COGNITIVE_OS.md`](./COGNITIVE_OS.md#phase-4--shader–cognition-bindings).