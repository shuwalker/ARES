// mysticVoidGeometry.metal — Geometry modifier for mysticVoid
// Mystic void environment: monolithic stone walls, floating tablets, Kabbalistic geometry, desaturated with bright accents

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

using namespace metal;

[[nodiscard]]
float3 mysticVoidGeometry(
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
