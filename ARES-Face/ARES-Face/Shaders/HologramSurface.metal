// HologramSurface.metal — Sci-fi projection with scan lines and chromatic aberration

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
void hologramSurface(realitykit::surface_parameters params,
                     constant SurfaceCustomUniforms &customParams) {
    float2 uv = params.geometry().uv0();
    float time = customParams.time;
    float intensity = customParams.intensity;
    float expression = customParams.expression;
    float isSpeaking = customParams.isSpeaking;

    float2 centered = uv - float2(0.5);
    float dist = length(centered);

    // Horizontal scan lines
    float scanLine = sin((uv.y + time * 0.15) * 120.0) * 0.5 + 0.5;
    float scanMask = smoothstep(0.35, 0.5, scanLine);

    // Random flicker / dropout blocks
    float2 blockUV = floor(uv * float2(16.0, 32.0));
    float noiseVal = hash21(blockUV + float2(0.0, floor(time * 10.0)));
    float dropout = 1.0 - step(0.92, noiseVal) * 0.7;

    // Chromatic aberration: offset R and B channel phases using UV
    float aberrationAmount = 0.008 * intensity;

    float rScan = sin((uv.y + time * 0.15) * 120.0 + aberrationAmount * 40.0) * 0.5 + 0.5;
    float gScan = sin((uv.y + time * 0.15) * 120.0)                         * 0.5 + 0.5;
    float bScan = sin((uv.y + time * 0.15) * 120.0 - aberrationAmount * 40.0) * 0.5 + 0.5;

    // Base cyan tint
    float3 cyan = float3(0.0, 0.85, 1.0);
    // Expression shifts hue slightly (more teal, more electric, etc.)
    float hueShift = 0.0;
    if (expression > 0.5 && expression < 1.5) {       // happy
        hueShift = 0.08;
    } else if (expression > 1.5 && expression < 2.5) { // curious
        hueShift = 0.15;
    } else if (expression > 2.5 && expression < 3.5) { // thinking
        hueShift = -0.05;
    } else if (expression > 3.5 && expression < 4.5) { // surprised
        hueShift = 0.12;
    } else if (expression > 4.5 && expression < 5.5) { // concerned
        hueShift = -0.10;
    } else if (expression > 5.5 && expression < 6.5) { // excited
        hueShift = 0.2;
    } else if (expression > 6.5) {                      // sleepy
        hueShift = -0.08;
    }
    cyan = float3(0.0 + clamp(hueShift, -0.2, 0.3), 0.85 - abs(hueShift) * 0.3, 1.0 - hueShift * 0.2);

    float3 color;
    color.r = cyan.r * smoothstep(0.35, 0.5, rScan) * dropout;
    color.g = cyan.g * smoothstep(0.35, 0.5, gScan) * dropout;
    color.b = cyan.b * smoothstep(0.35, 0.5, bScan) * dropout;

    // Vignette edges
    float vignette = 1.0 - smoothstep(0.35, 0.5, dist);
    color *= vignette;

    // Speaking: faster flicker
    if (isSpeaking > 0.5) {
        float speakPulse = 0.8 + 0.2 * sin(time * 16.0);
        color *= speakPulse;
    }

    // Opacity: holographic fade at edges + scan-gate alpha
    float opacity = intensity * vignette * scanMask * dropout;
    opacity = clamp(opacity * 1.5, 0.0, 1.0);

    params.surface().set_base_color(half3(color));
    params.surface().set_opacity(half(opacity));
}
