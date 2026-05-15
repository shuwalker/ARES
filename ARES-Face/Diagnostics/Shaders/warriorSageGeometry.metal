// warriorSageGeometry.metal — Geometry modifier for warriorSage
// Warrior sage: high-fidelity cel-shaded, narrow golden eyes, blonde beard lines, cool muted palette, white draped garment

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

using namespace metal;

[[nodiscard]]
float3 warriorSageGeometry(
    float3 position,
    float3 normal,
    RealityKit::GeometryParameters params
) {
    // Stub: pass through with subtle breathing animation
    float time = params.uniforms().vertexAnimationSpeed;
    float amplitude = params.uniforms().vertexAnimationAmplitude;
    float breath = sin(time) * amplitude;
    return position + normal * breath;
}
