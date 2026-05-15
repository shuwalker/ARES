// ConstellationGeometry.metal — Gentle drift with breathing scale, star-map feel

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

using namespace metal;

[[stitchable]]
void constellationGeometry(realitykit::geometry_parameters params,
                           constant GeometryCustomUniforms &customParams) {
    float3 pos = params.geometry().model_position();
    float time = params.uniforms().time();
    float speed = customParams.vertexAnimationSpeed;
    float amplitude = customParams.vertexAnimationAmplitude;
    float displacementScale = customParams.displacementScale;

    // Gentle drift — slow sinusoidal offset, like stars drifting in the sky
    float3 drift = float3(
        sin(pos.y * 3.0 + time * speed * 0.4) * amplitude * 0.5,
        cos(pos.x * 3.0 + time * speed * 0.3) * amplitude * 0.4,
        sin(pos.z * 2.0 + time * speed * 0.5) * amplitude * 0.3
    );

    // Breathing scale — subtle expansion/contraction
    float breathe = 1.0 + sin(time * speed * 0.8) * displacementScale * 0.02;
    float3 offset = drift * breathe * 0.003;

    params.geometry().set_model_position_offset(offset);
}
