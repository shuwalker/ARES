// HologramGeometry.metal — Flickering vertex jitter on normals

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

using namespace metal;

float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

[[stitchable]]
void hologramGeometry(realitykit::geometry_parameters params,
                      constant GeometryCustomUniforms &customParams) {
    float time = params.uniforms().time();
    float speed = customParams.vertexAnimationSpeed;
    float amplitude = customParams.vertexAnimationAmplitude;
    float scale = customParams.displacementScale;
    float normalInfluence = customParams.normalInfluence;

    float3 position = params.geometry().model_position();
    float3 normal = params.geometry().normal();

    // Flicker based on position hash
    float flicker = hash21(float2(floor(time * speed * 6.0), dot(position, float3(1.0, 2.0, 3.0)) * 4.0));
    float jitterAmount = (flicker < 0.85) ? 0.0 : 1.0;

    // Random jitter along normal
    float jPhase = sin(time * speed * 8.0 + position.x * 12.0) * 0.5 + 0.5;
    float displacement = jPhase * amplitude * scale * jitterAmount;

    float3 offset = normal * displacement * normalInfluence;

    params.geometry().set_model_position_offset(offset);
}
