// HologramSurface.metal — Sci-fi projection with scan lines, chromatic aberration, data-glitch eyes, and glitch mouth

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

    // Chromatic aberration
    float aberrationAmount = 0.008 * intensity;
    float rScan = sin((uv.y + time * 0.15) * 120.0 + aberrationAmount * 40.0) * 0.5 + 0.5;
    float gScan = sin((uv.y + time * 0.15) * 120.0)                               * 0.5 + 0.5;
    float bScan = sin((uv.y + time * 0.15) * 120.0 - aberrationAmount * 40.0) * 0.5 + 0.5;

    // Base cyan tint with hue shift
    float hueShift = 0.0;
    if (expression > 0.5 && expression < 1.5)       hueShift = 0.08;
    else if (expression > 1.5 && expression < 2.5)  hueShift = 0.15;
    else if (expression > 2.5 && expression < 3.5)  hueShift = -0.05;
    else if (expression > 3.5 && expression < 4.5)  hueShift = 0.12;
    else if (expression > 4.5 && expression < 5.5)  hueShift = -0.10;
    else if (expression > 5.5 && expression < 6.5)  hueShift = 0.2;
    else if (expression > 6.5)                       hueShift = -0.08;

    float3 cyan = float3(0.0 + clamp(hueShift, -0.2, 0.3),
                         0.85 - abs(hueShift) * 0.3,
                         1.0 - hueShift * 0.2);

    float3 color;
    color.r = cyan.r * smoothstep(0.35, 0.5, rScan) * dropout;
    color.g = cyan.g * smoothstep(0.35, 0.5, gScan) * dropout;
    color.b = cyan.b * smoothstep(0.35, 0.5, bScan) * dropout;

    // ======== EYES (intensity > 0.2) — angular holographic display eyes ========
    // Diamond-shaped eye approximations using rotated UV
    float2 leftEyeUV  = (uv - float2(0.38, 0.74)) * float2(1.0, 1.3);
    float2 rightEyeUV = (uv - float2(0.62, 0.74)) * float2(1.0, 1.3);
    float leftEyeD  = abs(leftEyeUV.x) / 0.07 + abs(leftEyeUV.y) / 0.10;
    float rightEyeD = abs(rightEyeUV.x) / 0.07 + abs(rightEyeUV.y) / 0.10;
    float eyes = max(smoothstep(1.0, 0.85, leftEyeD),
                     smoothstep(1.0, 0.85, rightEyeD));

    // Holographic eye "pupil" — a glowing vertical bar (like a computer cursor)
    float leftCursor  = smoothstep(0.01, 0.003, abs(leftEyeUV.x)) *
                        smoothstep(0.08, 0.04, abs(leftEyeUV.y));
    float rightCursor = smoothstep(0.01, 0.003, abs(rightEyeUV.x)) *
                        smoothstep(0.08, 0.04, abs(rightEyeUV.y));
    float cursors = max(leftCursor, rightCursor);

    // Eye data stream — horizontal dashes inside eyes
    float eyeDataL = sin(leftEyeUV.y * 40.0 + time * 5.0) * 0.5 + 0.5;
    float eyeDataR = sin(rightEyeUV.y * 44.0 + time * 5.3) * 0.5 + 0.5;
    float eyeData = max(
        step(0.7, eyeDataL) * smoothstep(1.0, 0.9, leftEyeD),
        step(0.7, eyeDataR) * smoothstep(1.0, 0.9, rightEyeD)
    );

    // Sleepy: display dims
    float sleepyDim = (expression > 6.5) ? 0.3 : 1.0;

    float3 eyeGlow = float3(0.0, 1.0, 0.9);
    float3 cursorColor = float3(0.2, 1.0, 1.0);
    float3 dataColor = float3(0.0, 0.6, 0.8);

    // ======== MOUTH — glitch bar that animates with speech ========
    // Horizontal mouth bar at UV (0.5, 0.28)
    float mouthPhase = isSpeaking > 0.5 ? 0.5 + 0.5 * sin(time * 12.0 + sin(time * 8.0)) : 0.2;
    float mouthBar = smoothstep(0.02 * mouthPhase, 0.005 * mouthPhase,
                                abs(uv.y - 0.28));
    float mouthWidth = smoothstep(0.10, 0.08, abs(uv.x - 0.5));

    // Glitch teeth — alternating bright/dark segments
    float teethSeg = step(0.5, fract(uv.x * 14.0 + time * 0.3));
    float mouth = mouthBar * mouthWidth;
    float teeth = mouth * teethSeg * (isSpeaking > 0.5 ? 1.0 : 0.3);

    float3 mouthBg = float3(0.0, 0.1, 0.15);
    float3 mouthFg = float3(0.0, 0.9, 1.0);

    // ======== COMPOSITING ========
    if (intensity > 0.2) {
        color = mix(color, eyeGlow * sleepyDim, eyes * 0.85);
        color = mix(color, cursorColor, cursors * 0.9);
        color = mix(color, dataColor, eyeData * 0.7 * sleepyDim);
    }

    if (isSpeaking > 0.5) {
        color = mix(color, mouthBg, mouth * 0.8);
        color = mix(color, mouthFg, teeth * 0.85);
    }

    // Vignette edges
    float vignette = 1.0 - smoothstep(0.35, 0.5, dist);
    color *= vignette;

    // Opacity
    float opacity = intensity * vignette * scanMask * dropout;
    if (intensity > 0.2) {
        opacity = max(opacity, eyes * intensity * 0.5);
    }
    opacity = clamp(opacity * 1.5, 0.0, 1.0);

    params.surface().set_base_color(half3(color));
    params.surface().set_opacity(half(opacity));
}
