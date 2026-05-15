// AnimeGeometry.metal — Slight breathe animation (scale pulse)

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

using namespace metal;

[[stitchable]]
void animeGeometry(realitykit::geometry_parameters params,
                   constant GeometryCustomUniforms &customParams) {
    float time = params.uniforms().time();
    float speed = customParams.vertexAnimationSpeed;
    float amplitude = customParams.vertexAnimationAmplitude;
    float scale = customParams.displacementScale;

    float3 position = params.geometry().model_position();

    // Breathe: slow scale pulse around center
    float breathe = sin(time * speed * 2.0) * amplitude * scale * 0.5;

    // Uniform radial expansion / contraction for breathing
    float3 offset = position * breathe;

    params.geometry().set_model_position_offset(offset);
}
