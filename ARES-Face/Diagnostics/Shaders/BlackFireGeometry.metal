// BlackFireGeometry.metal — Vertex displacement for flame-like motion v2
// Fast, chaotic displacement — not slow waves. Fire flickers, not ripples.

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

using namespace metal;

// Fast hash for vertex noise
float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

[[stitchable]]
void blackFireGeometry(realitykit::geometry_parameters params,
                       constant GeometryCustomUniforms &customParams) {
    float time = params.uniforms().time();
    float speed = customParams.vertexAnimationSpeed;
    float amplitude = customParams.vertexAnimationAmplitude;
    float scale = customParams.displacementScale;
    float normalInfluence = customParams.normalInfluence;
    
    float3 position = params.geometry().model_position();
    float3 normal = params.geometry().normal();
    
    // ── Fire displacement: fast, chaotic, upward-biased ──
    
    // Primary: fast upward flicker (not wave)
    float flicker1 = sin(time * speed * 2.0 + position.y * 3.5 + hash11(position.x * 10.0) * 6.28) 
                   * amplitude * scale;
    
    // Secondary: chaotic horizontal jitter — fire doesn't stay still
    float flicker2 = sin(time * speed * 3.7 + position.x * 5.0 + hash11(position.z * 7.0) * 6.28) 
                   * amplitude * scale * 0.25;
    
    // Tertiary: sharp micro-displacement for edge flicker
    float flicker3 = sin(time * speed * 7.1 + position.z * 9.0) 
                   * amplitude * scale * 0.08;
    
    // Combine: predominantly outward (normal), with upward bias (fire rises)
    float3 offset = normal * (flicker1 + flicker3) * normalInfluence;
    offset.y += flicker1 * 0.6 * scale;  // Strong upward push
    offset.x += flicker2 * 0.4 * scale;  // Horizontal jitter
    
    // Dampen at base (sphere bottom) — fire doesn't grow from the floor
    float baseDamp = smoothstep(-0.15, 0.1, position.y);
    offset *= baseDamp;
    
    params.geometry().set_model_position_offset(offset);
}