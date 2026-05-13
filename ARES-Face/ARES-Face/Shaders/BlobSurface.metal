// BlobSurface.metal — Metaball organism with soft glow and warm organic colors

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

using namespace metal;

float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < 5; i++) {
        value += amplitude * vnoise(p * frequency);
        frequency *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

[[stitchable]]
void blobSurface(realitykit::surface_parameters params,
                 constant SurfaceCustomUniforms &customParams) {
    float2 uv = params.geometry().uv0();
    float time = customParams.time;
    float intensity = customParams.intensity;
    float expression = customParams.expression;
    float isSpeaking = customParams.isSpeaking;

    float2 centered = uv - float2(0.5);
    float dist = length(centered);

    // Organic noise field
    float2 noiseUV = uv * 3.0 + float2(time * 0.2, time * 0.3);
    float n = fbm(noiseUV);
    float n2 = fbm(noiseUV * 2.3 + float2(time * 0.15, -time * 0.1));
    float combinedNoise = smoothstep(0.25, 0.75, n * 0.6 + n2 * 0.4);

    // Expression-driven hue: warm organic palette
    float hue = 0.08; // default peachy orange
    if (expression > 0.5 && expression < 1.5) {       // happy
        hue = 0.18;
    } else if (expression > 1.5 && expression < 2.5) { // curious
        hue = 0.28;
    } else if (expression > 2.5 && expression < 3.5) { // thinking
        hue = 0.05;
    } else if (expression > 3.5 && expression < 4.5) { // surprised
        hue = 0.12;
    } else if (expression > 4.5 && expression < 5.5) { // concerned
        hue = 0.72;
    } else if (expression > 5.5 && expression < 6.5) { // excited
        hue = 0.95;
    } else if (expression > 6.5) {                      // sleepy
        hue = 0.60;
    }

    float3 coreColor = hsv2rgb(float3(hue, 0.65, 0.95));
    float3 midColor  = hsv2rgb(float3(hue + 0.04, 0.75, 0.55));
    float3 edgeColor = hsv2rgb(float3(hue - 0.03, 0.85, 0.25));

    // Soft glow edges with distance falloff driven by noise (SDF-like metaball look)
    float sdfLike = smoothstep(0.0, 1.0, combinedNoise);
    float edgeGlow = smoothstep(0.55, 0.15, dist + (1.0 - sdfLike) * 0.3);
    float coreGlow = smoothstep(0.45, 0.0, dist - sdfLike * 0.2);

    float3 color = mix(edgeColor, midColor, edgeGlow);
    color = mix(color, coreColor, coreGlow);

    // Speaking: pulsing core brightness
    if (isSpeaking > 0.5) {
        float speakPulse = 0.85 + 0.15 * sin(time * 4.0);
        color *= speakPulse;
    }

    // Opacity: noise-modulated soft edges for metaball merge look
    float opacity = intensity * edgeGlow * 0.9 + coreGlow * intensity * 0.1;
    opacity = clamp(opacity * 1.2, 0.0, 1.0);

    params.surface().set_base_color(half3(color));
    params.surface().set_opacity(half(opacity));
}
