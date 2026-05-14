# ARES Context7 Reference — Key APIs (May 2026)

## RealityKit CustomMaterial

**Source:** Apple Developer Documentation via Context7
**URL:** https://developer.apple.com/documentation/realitykit/custommaterial

### Core API: CustomMaterial

Custom materials in RealityKit allow advanced rendering control using custom Metal 
shader functions. Two types of custom shaders:

1. **Geometry Modifier** — Alters vertex positions per frame (displacement, animation)
2. **Surface Shader** — Defines how pixels are colored (materials, effects, raymarching)

### Creating a CustomMaterial

```swift
// From existing material with surface shader and geometry modifier
let material = try CustomMaterial(
    from: existingMaterial,
    surfaceShader: CustomMaterial.SurfaceShader(named: "mySurfaceShader", in: library),
    geometryModifier: CustomMaterial.GeometryModifier(named: "myGeometryModifier", in: library)
)

// From scratch with surface shader, geometry modifier, and program descriptor
let material = try await CustomMaterial(
    surfaceShader: mySurfaceShader,
    geometryModifier: myGeometryModifier,
    descriptor: myDescriptor
)
```

### Custom Uniforms (shared between Swift and Metal)

```swift
// SharedHeader.h — bridged between Swift and Metal
#ifdef __METAL_VERSION__
#define TEXTURE_2D metal::texture2d<half>
#else
#define TEXTURE_2D uint64_t
#endif

typedef struct {
    TEXTURE_2D noiseTexture;
    float2 noiseUVOffset;
} SurfaceCustomUniforms;

typedef struct {
    float vertexAnimationSpeed;
    float vertexAnimationAmplitude;
} GeometryCustomUniforms;
```

### Metal Shader Functions

```metal
#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

constexpr sampler kSampler(coord::normalized, address::repeat, filter::linear);

// Surface shader — runs per pixel
[[stitchable]]
void surfaceShaderWithCustomUniforms(realitykit::surface_parameters params,
                                      constant SurfaceCustomUniforms &customParams)
{
    float2 uv = params.geometry().uv0();
    half4 noiseSample = customParams.noiseTexture.sample(kSampler, uv + customParams.noiseUVOffset);
    half4 baseColorSample = params.textures().base_color().sample(kSampler, uv);
    params.surface().set_base_color(baseColorSample.rgb + noiseSample.rgb);
}

// Geometry modifier — runs per vertex
[[stitchable]]
void geometryModifierWithCustomUniforms(realitykit::geometry_parameters params,
                                        constant GeometryCustomUniforms &customParams)
{
    float currentTime = params.uniforms().time() * customParams.vertexAnimationSpeed;
    params.geometry().set_model_position_offset(
        sin(currentTime) * customParams.vertexAnimationAmplitude * params.geometry().normal()
    );
}
```

### Setting Custom Uniforms from Swift

```swift
var customMaterial = CustomMaterial(surfaceShader: surfaceShader, lightingModel: .lit)

// Surface shader uniforms
customMaterial.withMutableUniforms(ofType: SurfaceCustomUniforms.self, stage: .surfaceShader) { params, resources in
    params.noiseUVOffset = SIMD2<Float>(x: 0.25, y: 0.25)
    resources[textureResource: \.noiseTexture] = noiseTexture
}

// Geometry modifier uniforms
customMaterial.withMutableUniforms(ofType: GeometryCustomUniforms.self, stage: .geometryModifier) { params, resources in
    params.vertexAnimationSpeed = 2.0
    params.vertexAnimationAmplitude = 0.1
}
```

### Key API Points for ARES

**GeometryModifier:**
- `params.geometry().set_model_position_offset(float3)` — Displace vertices
- `params.geometry().normal()` — Get vertex normal
- `params.geometry().uv0()` — Get UV coordinates
- `params.uniforms().time()` — Elapsed time (for animation)

**SurfaceShader:**
- `params.surface().set_base_color(float3/half3)` — Set pixel color
- `params.surface().set_opacity(float)` — Set transparency
- `params.textures().base_color()` — Access base color texture
- `params.geometry().uv0()` — Get UV coordinates
- Custom uniforms for intensity, expression, time, style parameters

**Stitchable vs Visible:**
- Use `[[stitchable]]` for shaders with custom uniforms
- Use `[[visible]]` for shaders without custom uniforms
- ARES uses `[[stitchable]]` since we pass FaceState uniforms

**Availability:**
- iOS 15.0+, macOS 12.0+, tvOS 26.0+, visionOS 1.0+
- Mac Catalyst 15.0+

### ARES Architecture Mapping

```
Swift (per frame)                    Metal (per vertex/pixel)
─────────────────                    ─────────────────────────
FaceState.intensity            →    GeometryCustomUniforms.intensity
FaceState.expression.rawValue  →    GeometryCustomUniforms.expression
FaceState.isSpeaking           →    GeometryCustomUniforms.isSpeaking
AvatarStyle.rawValue           →    SurfaceCustomUniforms.style
time                           →    params.uniforms().time()

Swift:                              Metal:
customMaterial.withMutableUniforms  [[stitchable]]
  (ofType: ..., stage: .surface)    void blackFireSurface(...)
  (ofType: ..., stage: .geometry)   void blackFireGeometry(...)
```

### Style Switching

Each style is a different Metal function. Switch by creating a new material
with different shader names, or by using a style uniform in a single shader
that branches:

```swift
// Option A: Separate materials per style (cleaner, recommended)
func setAvatarStyle(_ style: AvatarStyle) {
    avatarEntity.model?.materials = [styleMaterials[style]]
}

// Option B: Uniform-driven branching in single shader (more flexible)
// In Metal: if (style == 0) { fireColor = ... } else if (style == 1) { animeColor = ... }
```

---

## RealityKit Scene Management

```swift
// RealityView in SwiftUI
RealityView { content in
    // Setup: create entities, add to content
    let avatarEntity = ModelEntity(mesh: .generateSphere(radius: 0.15))
    content.add(avatarEntity)
} update: { content in
    // Update: modify entities per frame
}

// Entity loading (USDZ, glTF)
let robotModel = try await Entity.loadModel(named: "JP01_arm")

// Physics
robotModel.components[PhysicsBodyComponent.self] = PhysicsBodyComponent(
    massProperties: .default,
    mode: .static
)

// Collision
robotModel.components[CollisionComponent.self] = CollisionComponent(
    shapes: [.generateBox(size: [0.5, 0.5, 0.5])]
)

// Animation
let animation = try await AnimationResource.loadAnimation(named: "idle")
robotModel.playAnimation(animation)
```

---

## Note: API Verification

Context7 pulled Apple's official RealityKit documentation. The CustomMaterial API
with GeometryModifier, SurfaceShader, and withMutableUniforms is confirmed available
on macOS 12+, iOS 15+, visionOS 1.0+. Our M1 Max running macOS 26.3.1 with Xcode 26.5 
and Swift 6.3.2 supports all of these APIs.

The `[[stitchable]]` attribute (required for custom uniforms) is the correct attribute
for our use case. The `RealityKit/RealityKit.h` Metal header provides the 
`realitykit::surface_parameters` and `realitykit::geometry_parameters` types.