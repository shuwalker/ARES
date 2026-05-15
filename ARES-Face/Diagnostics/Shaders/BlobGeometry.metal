// BlobGeometry.metal — Spring-connected vertex displacement (pull toward center and bounce)

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

using namespace metal;

[[stitchable]]
void blobGeometry(realitykit::geometry_parameters params,
                  constant GeometryCustomUniforms &customParams) {
    float time = params.uniforms().time();
    float speed = customParams.vertexAnimationSpeed;
    float amplitude = customParams.vertexAnimationAmplitude;
    float scale = customParams.displacementScale;
    float normalInfluence = customParams.normalInfluence;

    float3 position = params.geometry().model_position();
    float3 normal = params.geometry().normal();

    // Distance from center for spring attenuation
    float dist = length(position);

    // Spring-bounce: vertices pull toward center and bounce back
    float bounce = sin(time * speed * 3.0 + dist * 6.0) * amplitude * scale;
    // Secondary slower spring
    float bounce2 = sin(time * speed * 1.7 + dist * 3.0 + 1.5) * amplitude * scale * 0.5;

    // Displace along normal (outward/inward spring)
    float displacement = (bounce + bounce2) * normalInfluence;

    float3 offset = normal * displacement;

    params.geometry().set_model_position_offset(offset);
}
