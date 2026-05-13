// AnimeSurface.metal — Cel-shaded anime surface with outline effect

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

float3 hsv2rgb(float3 c) {
    float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
    float3 p = abs(fract(c.xxx + K.xyz) * 6.0 - K.www);
    return c.z * mix(K.xxx, clamp(p - K.xxx, 0.0, 1.0), c.y);
}

[[stitchable]]
void animeSurface(realitykit::surface_parameters params,
                  constant SurfaceCustomUniforms &customParams) {
    float2 uv = params.geometry().uv0();
    float time = customParams.time;
    float intensity = customParams.intensity;
    float expression = customParams.expression;
    float isSpeaking = customParams.isSpeaking;

    // Center and edge distance for outline
    float2 centered = uv - float2(0.5);
    float dist = length(centered);

    // Base shape silhouette using normal-derived rim (approximate via UV edge)
    // Cel shading: quantize dot product into 3-4 hard bands
    float3 normal = params.geometry().normal();
    float3 lightDir = normalize(float3(0.5, 0.8, 0.3));
    float NdotL = dot(normal, lightDir);

    // Hard-edge cel bands
    float celBand;
    if (NdotL > 0.65) {
        celBand = 1.0;   // Highlight
    } else if (NdotL > 0.25) {
        celBand = 0.55;  // Midtone
    } else if (NdotL > -0.1) {
        celBand = 0.25;  // Shadow
    } else {
        celBand = 0.08;  // Deep shadow
    }

    // Outline: darken near UV boundaries (rim approximation)
    float edgeDist = smoothstep(0.52, 0.45, dist); // inner-to-outer ramp reversed
    float outline = 0.0;
    if (edgeDist > 0.65) {
        outline = 1.0;
    }

    // Expression-driven hue shift
    float baseHue = 0.58; // default blue
    if (expression > 0.5 && expression < 1.5) {       // happy
        baseHue = 0.35;
    } else if (expression > 1.5 && expression < 2.5) { // curious
        baseHue = 0.75;
    } else if (expression > 2.5 && expression < 3.5) { // thinking
        baseHue = 0.15;
    } else if (expression > 3.5 && expression < 4.5) { // surprised
        baseHue = 0.08;
    } else if (expression > 4.5 && expression < 5.5) { // concerned
        baseHue = 0.65;
    } else if (expression > 5.5 && expression < 6.5) { // excited
        baseHue = 0.92;
    } else if (expression > 6.5) {                      // sleepy
        baseHue = 0.72;
    }

    float3 baseColor = hsv2rgb(float3(baseHue, 0.7, celBand));
    float3 outlineColor = hsv2rgb(float3(baseHue + 0.02, 0.9, 0.04));
    float3 finalColor = mix(baseColor, outlineColor, outline);

    // Slight grain texture for paper-like feel
    float grain = vnoise(uv * 400.0) * 0.04;
    finalColor += grain;

    // Speaking pulse
    if (isSpeaking > 0.5) {
        float speakPulse = 0.9 + 0.1 * sin(time * 10.0);
        finalColor *= speakPulse;
    }

    // Opacity: stronger edge outline visibility
    float opacity = intensity * (1.0 - smoothstep(0.48, 0.52, dist) * 0.35);
    opacity = clamp(opacity, 0.0, 1.0);

    params.surface().set_base_color(half3(finalColor));
    params.surface().set_opacity(half(opacity));
}
