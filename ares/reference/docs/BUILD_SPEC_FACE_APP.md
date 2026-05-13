# ARES Face App — Build Specification

## What We're Building

A native macOS app (SwiftUI + RealityKit + Metal) that renders the ARES companion
face with cinematic quality, connects to the Python brain via WebSocket, and
provides a foundation for engineering model visualization.

The existing POC (`ares/reference/swift-ui/ARESApp.swift`) is a Canvas-drawn
proof of concept with bezier curve fire. We are replacing it with a RealityKit
scene using CustomMaterial Metal shaders for CGI-quality rendering.

## Hardware Target

- Mac Studio M1 Max (24 GPU cores, 32GB unified memory, Metal 4)
- macOS 26 (Tahoe), Xcode 26.5, Swift 6.3.2
- All frameworks confirmed present: RealityKit, Metal, MetalKit, MetalPerformanceShaders, SwiftUI

## Architecture

```
┌─────────────────────────────────────────────────┐
│  ARESApp.swift (entry point)                    │
│  └── MenuBarExtra + WindowGroup                  │
│       └── ARESRootView                           │
│            ├── ImmersionBar                      │
│            ├── AvatarSceneView (RealityView)     │
│            │    └── RealityKit Scene              │
│            │         ├── AvatarEntity             │
│            │         │    └── CustomMaterial      │
│            │         │         ├── .metal shaders │
│            │         │         └── uniforms       │
│            │         └── (future: robot models)   │
│            ├── ChatStream                         │
│            └── CommandBar                         │
│                                                  │
│  BrainConnection.swift (WebSocket client)        │
│  └── URLSessionWebSocketTask → localhost:7860/ws │
│       └── receives: face_state, chat messages    │
│       └── sends: chat messages, commands         │
│                                                  │
│  AvatarStyle.swift (style registry)              │
│  └── blackFire, anime, hologram, blob,          │
│     pixelVolume, constellation                  │
│                                                  │
│  Shaders/                                        │
│  ├── BlackFireSurface.metal                      │
│  ├── BlackFireGeometry.metal                     │
│  ├── AnimeSurface.metal                          │
│  ├── HologramSurface.metal                       │
│  ├── BlobSurface.metal                           │
│  ├── PixelVolumeSurface.metal                    │
│  └── ConstellationSurface.metal                 │
└─────────────────────────────────────────────────┘
```

## FaceState Protocol (from Python Brain)

The Python brain sends FaceState via WebSocket at `localhost:7860/ws`:

```json
{
  "type": "face_state",
  "state": "thinking",
  "emotion": "curious",
  "intensity": 0.85,
  "timestamp": 1715632800.123
}
```

Valid states: `idle`, `awakened`, `listening`, `thinking`, `speaking`, `sleeping`

Python `FaceConfig` maps states to visual parameters:
- color: RGB tuple (0-1)
- opacity: float (0-1)
- pulse_speed: float (cycles/sec)
- pulse_amount: float (0-1)
- pupil_offset: (x, y) tuple (-1 to 1)

The Swift app receives these and maps them to Metal shader uniforms.

## WebSocket Message Types

### Client → Server (Swift sends)
```json
{"type": "chat", "text": "Hello ARES", "session_id": "uuid"}
{"type": "command", "command": "set_face", "args": {"state": "thinking"}}
{"type": "ping"}
```

### Server → Client (Python sends)
```json
{"type": "face_state", "state": "thinking", "emotion": "curious", "intensity": 0.85}
{"type": "chat_response", "text": "I'm thinking about that...", "session_id": "uuid"}
{"type": "personality_update", "layer": "expression", "trait": "verbosity", "value": 0.7}
{"type": "pong", "timestamp": 1715632800.123}
```

### REST Endpoints (fallback)
- GET  `/api/status` — system status
- GET  `/api/face` — current face state
- POST `/api/face` — set face state
- GET  `/api/identity` — ARES identity info
- GET  `/api/personality` — personality traits
- POST `/api/personality` — update traits
- POST `/api/chat` — send message, get response

## CustomMaterial API (from Context7 Apple Docs)

### Creating a CustomMaterial

```swift
// Load the Metal library
let library = MTLCreateSystemDefaultDevice()!.makeDefaultLibrary()!

// Create surface shader
let surfaceShader = CustomMaterial.SurfaceShader(
    named: "blackFireSurface", in: library
)

// Create geometry modifier
let geometryModifier = CustomMaterial.GeometryModifier(
    named: "blackFireGeometry", in: library
)

// Create material
let material = try CustomMaterial(
    from: SimpleMaterial(color: .black, isMetallic: false),
    surfaceShader: surfaceShader,
    geometryModifier: geometryModifier
)

// Update uniforms per frame
material.withMutableUniforms(ofType: AvatarUniforms.self, stage: .surfaceShader) { params, resources in
    params.intensity = 0.85
    params.expression = 1  // thinking
    params.isSpeaking = false
    params.time = Float(CACurrentMediaTime())
}
```

### Metal Shader Structure (SharedHeader.h)

```objc
#ifdef __METAL_VERSION__
#define TEXTURE_2D metal::texture2d<half>
#else
#define TEXTURE_2D uint64_t
#endif

typedef struct {
    float intensity;       // 0.0 - 1.0
    float expression;      // 0=neutral, 1=happy, 2=curious, 3=thinking, etc.
    float isSpeaking;      // 0.0 or 1.0
    float time;            // elapsed seconds
} SurfaceCustomUniforms;

typedef struct {
    float vertexAnimationSpeed;
    float vertexAnimationAmplitude;
    float displacementScale;
    float normalInfluence;
} GeometryCustomUniforms;
```

### Metal Shader Example (BlackFireSurface.metal)

```metal
#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

constexpr sampler kSampler(coord::normalized, address::repeat, filter::linear);

[[stitchable]]
void blackFireSurface(realitykit::surface_parameters params,
                      constant SurfaceCustomUniforms &customParams) {
    float2 uv = params.geometry().uv0();
    float time = customParams.time;
    float intensity = customParams.intensity;

    // Procedural noise for fire
    float noise = sin(uv.x * 10.0 + time * 3.0) * cos(uv.y * 8.0 + time * 2.0);

    // Base fire colors (dark violet / black body)
    float3 coreColor = float3(0.65, 0.30, 1.0) * intensity;  // violet core
    float3 outerColor = float3(0.06, 0.01, 0.18) * intensity; // dark edge

    // Mix based on noise and distance from center
    float dist = length(uv - float2(0.5));
    float3 color = mix(coreColor, outerColor, smoothstep(0.0, 0.5, dist + noise * 0.3));

    params.surface().set_base_color(half3(color));
    params.surface().set_opacity(half(intensity));
}
```

### Geometry Modifier Example (BlackFireGeometry.metal)

```metal
#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

[[stitchable]]
void blackFireGeometry(realitykit::geometry_parameters params,
                       constant GeometryCustomUniforms &customParams) {
    float time = params.uniforms().time();
    float speed = customParams.vertexAnimationSpeed;
    float amplitude = customParams.vertexAnimationAmplitude;
    float3 normal = params.geometry().normal();

    // Flame-like upward displacement
    float displacement = sin(time * speed) * amplitude;
    params.geometry().set_model_position_offset(normal * displacement);
}
```

### Style Switching

Each style is a different Metal function. Switch by creating a new material:

```swift
func setAvatarStyle(_ style: AvatarStyle) {
    let surfaceName = style.surfaceShaderName  // e.g. "blackFireSurface"
    let geoName = style.geometryModifierName    // e.g. "blackFireGeometry"

    let surfaceShader = CustomMaterial.SurfaceShader(named: surfaceName, in: library)!
    let geoModifier = CustomMaterial.GeometryModifier(named: geoName, in: library)!

    let newMaterial = try! CustomMaterial(
        from: SimpleMaterial(color: .black, isMetallic: false),
        surfaceShader: surfaceShader,
        geometryModifier: geoModifier
    )

    avatarEntity.model?.materials = [newMaterial]
}
```

### AvatarStyle enum

```swift
enum AvatarStyle: String, CaseIterable, Codable {
    case blackFire
    case anime
    case hologram
    case blob
    case pixelVolume
    case constellation

    var surfaceShaderName: String {
        switch self {
        case .blackFire:      return "blackFireSurface"
        case .anime:          return "animeSurface"
        case .hologram:       return "hologramSurface"
        case .blob:           return "blobSurface"
        case .pixelVolume:   return "pixelVolumeSurface"
        case .constellation:  return "constellationSurface"
        }
    }

    var geometryModifierName: String {
        switch self {
        case .blackFire:      return "blackFireGeometry"
        case .anime:          return "animeGeometry"
        case .hologram:       return "hologramGeometry"
        case .blob:           return "blobGeometry"
        case .pixelVolume:   return "pixelVolumeGeometry"
        case .constellation:  return "constellationGeometry"
        }
    }
}
```

## Existing POC Reference

The POC (810 lines) has these working features to PORT, not copy:

1. **ARESWorld** state manager — maps agent states to visual params
2. **VoiceManager** — AVFoundation mic/speaker (macOS uses NSSpeechRecognizer)
3. **Immersion levels** — Desktop/Window/Room
4. **Chat UI** — messages, input, send
5. **MenuBarExtra** — always-on menu bar presence
6. **AgentState enum** — idle/awakened/listening/thinking/speaking/sleeping
7. **AvatarExpression enum** — neutral/happy/curious/thinking/surprised/concerned/excited/sleepy
8. **HTTPClient** — REST to brain at localhost:9876 (CHANGE to :7860 + WebSocket)

Key differences in the new version:
- AvatarView uses RealityView + CustomMaterial instead of Canvas
- HTTPClient becomes BrainConnection with WebSocket
- BlackFireSystem.swift (CPU particle sim) removed — replaced by Metal GPU shaders
- fireIntensity/expressionBoost moved into Metal uniforms
- expressionTint() moved into Metal shader as uniform

## Xcode Project Structure

```
ARES-Face/
├── ARES-Face.xcodeproj/
├── ARES-Face/
│   ├── App/
│   │   ├── ARESApp.swift              # @main entry, WindowGroup + MenuBarExtra
│   │   └── ARESRootView.swift         # Root layout (immersion bar, avatar, chat, input)
│   ├── Models/
│   │   ├── AgentState.swift           # Enum: idle/awakened/listening/thinking/speaking/sleeping
│   │   ├── AvatarExpression.swift     # Enum: neutral/happy/curious/thinking/surprised/concerned/excited/sleepy
│   │   ├── AvatarStyle.swift          # Enum: blackFire/anime/hologram/blob/pixelVolume/constellation
│   │   ├── ImmersionLevel.swift       # Enum: light/medium/full
│   │   ├── ARESMessage.swift          # Chat message model
│   │   └── FaceConfig.swift           # Visual parameters per state (intensity, color, pulse, pupils)
│   ├── Networking/
│   │   └── BrainConnection.swift      # WebSocket client to localhost:7860/ws
│   ├── Views/
│   │   ├── AvatarSceneView.swift      # RealityView + scene setup + AvatarEntity
│   │   ├── ChatStream.swift           # Message list
│   │   ├── CommandBar.swift           # Input text field + mic + send
│   │   ├── ImmersionBar.swift         # Desktop/Window/Room + state indicator
│   │   └── MenuBarView.swift          # Menu bar dropdown
│   ├── Rendering/
│   │   ├── AvatarRenderer.swift       # CustomMaterial creation, uniform updates, style switching
│   │   ├── AvatarEntity.swift         # Mesh generation (sphere base) + model component setup
│   │   └── SceneSetup.swift           # Lighting, camera, environment for the RealityView scene
│   ├── Shaders/
│   │   ├── SharedHeader.h             # Shared uniforms struct (Metal + Swift bridge)
│   │   ├── BlackFireSurface.metal     # Black fire surface shader
│   │   ├── BlackFireGeometry.metal    # Black fire geometry modifier
│   │   ├── AnimeSurface.metal         # Cel-shaded anime surface
│   │   ├── AnimeGeometry.metal        # Anime vertex animation
│   │   ├── HologramSurface.metal      # Scan lines + chromatic aberration
│   │   ├── HologramGeometry.metal      # Hologram flicker displacement
│   │   ├── BlobSurface.metal          # Metaball organic surface
│   │   ├── BlobGeometry.metal         # Metaball smooth merge
│   │   ├── PixelVolumeSurface.metal   # Voxelized density surface
│   │   ├── PixelVolumeGeometry.metal  # Voxel snap displacement
│   │   ├── ConstellationSurface.metal # Point cloud + triangulation
│   │   └── ConstellationGeometry.metal # Vertex scatter
│   └── Voice/
│       └── VoiceManager.swift         # AVFoundation mic + NSSpeechRecognizer + TTS
├── ARES-FaceTests/
│   └── AvatarRendererTests.swift
└── ARES-FaceUITests/
    └── AvatarSceneUITests.swift
```

## Implementation Priority

Phase 1 — SCAFFOLD (this task):
1. Xcode project with proper target (macOS 13+, Swift 6)
2. All file structure above (empty files with stubs)
3. SharedHeader.h with uniform structs
4. BlackFireSurface.metal + BlackFireGeometry.metal (FIRST style, working)
5. AvatarRenderer.swift that creates CustomMaterial and updates uniforms
6. AvatarEntity.swift that creates sphere mesh with the material
7. AvatarSceneView.swift with RealityView showing the black fire entity
8. BrainConnection.swift with WebSocket client
9. ARESApp.swift with WindowGroup + MenuBarExtra
10. Port over: AgentState, AvatarExpression, ARESMessage, ImmersionLevel, VoiceManager
11. Build and run — see a black fire sphere in a window

Phase 2 — STYLES (next task):
1. Remaining 5 shader styles (anime, hologram, blob, pixelVolume, constellation)
2. Style switcher UI in ImmersionBar
3. Per-style uniform tuning

Phase 3 — ENGINEERING VIZ (future):
1. USDZ/glTF model loading
2. Camera orbit/zoom/pan
3. FEA stress map overlay material
4. Robot joint visualization
5. Cross-section views

## Key Constraints

1. `[[stitchable]]` attribute on all Metal functions (required for custom uniforms)
2. `RealityKit/RealityKit.h` must be included in all .metal files
3. CustomMaterial requires macOS 12.0+ (we target macOS 13+)
4. Uniform structs shared between Swift and Metal via SharedHeader.h bridging
5. Texture types need `#ifdef __METAL_VERSION__` bridge (TEXTURE_2D → uint64_t in Swift, metal::texture2d<half> in Metal)
6. WebSocket URL: `ws://localhost:7860/ws`
7. REST API base: `http://localhost:7860/api`
8. The app must work WITHOUT the brain running (show idle state, graceful fallback)

## Testing

- Manual: launch `ares serve` on port 7860, then launch ARES-Face.app
- Automated: unit tests for BrainConnection, AvatarRenderer material creation, FaceConfig mapping
- Visual: each style should render distinctly in the RealityView

## What NOT To Do

1. Do NOT use SwiftUI Canvas for the avatar — use RealityView + CustomMaterial
2. Do NOT use SimpleMaterial or UnlitMaterial for the avatar — use CustomMaterial
3. Do NOT embed Unity or any third-party engine
4. Do NOT copy the POC code verbatim — port the state/enum/UI patterns, rewrite the rendering
5. Do NOT hard-code shader names in multiple places — use AvatarStyle enum
6. Do NOT use the old HTTPClient — use BrainConnection with WebSocket
7. Do NOT use the old Canvas-based AnimeFireEntity — replace entirely with RealityKit entity