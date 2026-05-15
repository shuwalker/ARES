// warriorSageSurface.metal — Warrior sage: high-fidelity cel-shaded, narrow golden eyes, blonde beard lines, cool muted palette, white draped garment
// Palette: skin=#F5DEB3 shadow=#8B7355 hair=#DAA520 eye=#FFD700
// TODO: Full implementation — currently a minimal stub that renders a lit material

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

using namespace metal;

[[nodiscard]]
fragment half4 warriorSageSurface(
    RealityKit::SurfaceInput surface_input,
    RealityKit::Framebuffer fb,
    uint2 coord,
    RealityKit::SurfaceParameters params
) {
    // Stub: render with basic lighting and a tint based on expression
    half4 base = half4(0.5, 0.3, 0.7, 1.0); // placeholder purple
    float expr = params.uniforms().expression;
    float intensity = params.uniforms().intensity;
    float time = params.uniforms().time;
    
    // Pulse based on intensity
    half4 result = half4(base.rgb * (0.5 + 0.5 * intensity), base.a);
    return result;
}
