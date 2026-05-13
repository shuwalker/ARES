// BlackFireGeometry.metal — Vertex displacement for flame-like upward motion

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

using namespace metal;

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
    
    // Upward flame displacement — stronger at top, oscillating
    // Primary wave: slow undulation
    float wave1 = sin(time * speed + position.y * 4.0) * amplitude * scale;
    // Secondary wave: faster flicker
    float wave2 = sin(time * speed * 2.3 + position.x * 6.0) * amplitude * scale * 0.3;
    // Tertiary: chaotic detail
    float wave3 = sin(time * speed * 4.1 + position.z * 8.0) * amplitude * scale * 0.15;
    
    float displacement = wave1 + wave2 + wave3;
    
    // Displace primarily along normals (for sphere, outward)
    // with a slight upward bias for flame motion
    float3 offset = normal * displacement * normalInfluence;
    offset.y += wave1 * 0.5 * scale;  // Upward bias
    
    params.geometry().set_model_position_offset(offset);
}