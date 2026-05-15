// synthMuseGeometry.metal — Geometry modifier for synthMuse
// Cyberpunk synth-muse: cel-shaded lavender skin, magenta slit eyes, 3 diagonal cheek stripes, cyan rim light, bob hair shadow

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

using namespace metal;

[[nodiscard]]
float3 synthMuseGeometry(
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
