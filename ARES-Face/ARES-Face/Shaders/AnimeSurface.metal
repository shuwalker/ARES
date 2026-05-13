// AnimeSurface.metal — Cel-shaded anime surface with bold outline, character eyes, and mouth

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

// Smooth eye shape using two UV circles (left and right eye positions)
float eyeShape(float2 uv, float2 eyeCenter, float eyeRadiusX, float eyeRadiusY) {
    float2 delta = uv - eyeCenter;
    float d = (delta.x * delta.x) / (eyeRadiusX * eyeRadiusX) +
              (delta.y * delta.y) / (eyeRadiusY * eyeRadiusY);
    return smoothstep(1.0, 0.85, d);
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

    // Base cel shading from normal
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
    float edgeDist = smoothstep(0.52, 0.45, dist);
    float outline = edgeDist > 0.65 ? 1.0 : 0.0;

    // Expression-driven hue shift
    float baseHue = 0.58;
    if (expression > 0.5 && expression < 1.5)       baseHue = 0.35;   // happy — warm
    else if (expression > 1.5 && expression < 2.5)  baseHue = 0.75;   // curious
    else if (expression > 2.5 && expression < 3.5)  baseHue = 0.15;   // thinking
    else if (expression > 3.5 && expression < 4.5)  baseHue = 0.08;   // surprised
    else if (expression > 4.5 && expression < 5.5)  baseHue = 0.65;   // concerned
    else if (expression > 5.5 && expression < 6.5)  baseHue = 0.92;   // excited
    else if (expression > 6.5)                       baseHue = 0.72;  // sleepy

    float3 baseColor = hsv2rgb(float3(baseHue, 0.7, celBand));
    float3 outlineColor = hsv2rgb(float3(baseHue + 0.02, 0.9, 0.04));

    // ======== EYES (intensity > 0.2) ========
    // Left eye at UV (0.38, 0.72), right eye at (0.62, 0.72)
    float leftEye  = eyeShape(uv, float2(0.38, 0.72), 0.06, 0.09);
    float rightEye = eyeShape(uv, float2(0.62, 0.72), 0.06, 0.09);
    float eyes = max(leftEye, rightEye);

    // Pupil — small dark circle inside eye
    float leftPupil  = eyeShape(uv, float2(0.38, 0.715), 0.025, 0.04);
    float rightPupil = eyeShape(uv, float2(0.62, 0.715), 0.025, 0.04);
    float pupils = max(leftPupil, rightPupil);

    // Eye highlight sparkle
    float sparkleL = eyeShape(uv, float2(0.365, 0.74), 0.012, 0.015);
    float sparkleR = eyeShape(uv, float2(0.605, 0.74), 0.012, 0.015);
    float sparkles = max(sparkleL, sparkleR);

    // Sleepy: eyelids half-close by shrinking eye height with expression
    float eyelid = (expression > 6.5) ? smoothstep(0.73, 0.685, uv.y) : 0.0;

    float3 eyeWhite = float3(1.0);
    float3 pupilColor = float3(0.02, 0.02, 0.06);
    float3 sparkleColor = float3(1.0);

    // ======== MOUTH (isSpeaking > 0.5) ========
    // Simple curved mouth at UV (0.5, 0.32)
    float mouthDist = length((uv - float2(0.5, 0.32)) * float2(1.0, 2.5));
    float mouthAnim = (isSpeaking > 0.5) ? 0.5 + 0.5 * sin(time * 10.0 + sin(time * 7.0) * 2.0) : 0.3;
    float mouth = smoothstep(0.08 * mouthAnim, 0.02 * mouthAnim, mouthDist);
    float3 mouthColor = float3(0.05, 0.01, 0.02);

    // ======== COMPOSITING ========
    float3 finalColor = mix(baseColor, outlineColor, outline);

    // Apply eyes over base
    if (intensity > 0.2) {
        finalColor = mix(finalColor, eyeWhite, eyes * 0.95);
        finalColor = mix(finalColor, pupilColor, pupils * 0.95);
        finalColor = mix(finalColor, sparkleColor, sparkles * 0.9);
        finalColor = mix(finalColor, baseColor * 0.5, eyelid);  // eyelid overlay
    }

    // Apply mouth
    if (isSpeaking > 0.5) {
        finalColor = mix(finalColor, mouthColor, mouth * 0.85);
    }

    // Slight grain texture for paper-like feel
    float grain = vnoise(uv * 400.0) * 0.04;
    finalColor += grain;

    // Opacity: stronger edge outline visibility
    float opacity = intensity * (1.0 - smoothstep(0.48, 0.52, dist) * 0.35);
    opacity = clamp(opacity, 0.0, 1.0);

    // Eyes should be opaque when present
    if (intensity > 0.2) {
        opacity = max(opacity, eyes * intensity * 0.7);
    }

    params.surface().set_base_color(half3(finalColor));
    params.surface().set_opacity(half(opacity));
}
