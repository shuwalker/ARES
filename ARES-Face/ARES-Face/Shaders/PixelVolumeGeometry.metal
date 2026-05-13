// PixelVolumeGeometry.metal — Snap vertices to quantized grid

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

using namespace metal;

[[stitchable]]
void pixelVolumeGeometry(realitykit::geometry_parameters params,
                         constant GeometryCustomUniforms &customParams) {
    float3 position = params.geometry().model_position();
    float scale = customParams.displacementScale;

    // Snap model-space position to a voxel grid step
    float stepSize = 1.0 / 12.0; // grid step relative to model space
    float3 snapped = round(position / stepSize) * stepSize;

    // Blend snap amount with scale
    float3 offset = (snapped - position) * scale;

    params.geometry().set_model_position_offset(offset);
}
