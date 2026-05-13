// PixelVolumeSurface.metal — Voxel density with quantized grid blocks and expression-driven color

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

using namespace metal;

float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

[[stitchable]]
void pixelVolumeSurface(realitykit::surface_parameters params,
                        constant SurfaceCustomUniforms &customParams) {
    float2 uv = params.geometry().uv0();
    float time = customParams.time;
    float intensity = customParams.intensity;
    float expression = customParams.expression;
    float isSpeaking = customParams.isSpeaking;

    // Voxel grid quantization
    float gridSize = 24.0;
    float2 gridUV = floor(uv * gridSize) / gridSize;
    float2 cellCenter = gridUV + (0.5 / gridSize);

    float2 centered = cellCenter - float2(0.5);
    float dist = length(centered);

    // Per-voxel density from hash (deterministic per cell)
    float cellHash = hash21(gridUV * 3.7 + float2(1.337, 2.718));

    // Expression-driven base hue
    float hue = 0.15; // default amber voxel
    if (expression > 0.5 && expression < 1.5) {       // happy
        hue = 0.25;
    } else if (expression > 1.5 && expression < 2.5) { // curious
        hue = 0.45;
    } else if (expression > 2.5 && expression < 3.5) { // thinking
        hue = 0.65;
    } else if (expression > 3.5 && expression < 4.5) { // surprised
        hue = 0.55;
    } else if (expression > 4.5 && expression < 5.5) { // concerned
        hue = 0.72;
    } else if (expression > 5.5 && expression < 6.5) { // excited
        hue = 0.88;
    } else if (expression > 6.5) {                      // sleepy
        hue = 0.60;
    }

    // Voxel lit by density: brighter for center-dense cells
    float density = smoothstep(0.55, 0.0, dist) * (0.5 + cellHash * 0.5);
    float3 baseColor = hsv2rgb(float3(hue, 0.9, density));
    // Darker edges for block definition
    float3 edgeColor = hsv2rgb(float3(hue, 0.95, density * 0.25));

    // Grid edge detection for block outlines
    float2 fracUV = fract(uv * gridSize);
    float edge = smoothstep(0.0, 0.08, fracUV.x) * smoothstep(1.0, 0.92, fracUV.x) *
                 smoothstep(0.0, 0.08, fracUV.y) * smoothstep(1.0, 0.92, fracUV.y);

    float3 color = mix(edgeColor, baseColor, edge);

    // Speaking: pulsing density
    if (isSpeaking > 0.5) {
        float speakPulse = 0.85 + 0.15 * sin(time * 6.0);
        color *= speakPulse;
    }

    // Opacity: drop out sparse outer voxels for density-volume look
    float occupancy = step(0.35, density + cellHash * 0.15);
    float opacity = intensity * occupancy * edge;
    opacity = clamp(opacity * 1.4, 0.0, 1.0);

    params.surface().set_base_color(half3(color));
    params.surface().set_opacity(half(opacity));
}
