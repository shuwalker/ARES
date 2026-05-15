// companionGeometry.metal — Geometry modifier for companion
// Ball companion in glass dome: fuzzy dark sphere with single red slit-pupil eye and wide toothy grin, transforms between states

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

using namespace metal;

[[nodiscard]]
float3 companionGeometry(
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
