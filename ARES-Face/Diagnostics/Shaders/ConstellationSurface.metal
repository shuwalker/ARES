// ConstellationSurface.metal — Star map with twinkling points, connecting lines, constellation eyes, and nebula mouth

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

using namespace metal;

float hash21c(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float twinkle(float2 uv, float time, float seed) {
    float phase = hash21c(uv + seed) * 6.2831;
    float speed = 1.0 + hash21c(uv * 2.0 + seed) * 3.0;
    float t = sin(time * speed + phase) * 0.5 + 0.5;
    return t * t;
}

// Smooth circle for star/eye
float circle(float2 uv, float2 center, float radius) {
    return smoothstep(radius, radius * 0.7, length(uv - center));
}

[[stitchable]]
void constellationSurface(realitykit::surface_parameters params,
                          constant SurfaceCustomUniforms &customParams) {
    float2 uv = params.geometry().uv0();
    float time = customParams.time;
    float intensity = customParams.intensity;
    float expression = customParams.expression;
    float isSpeaking = customParams.isSpeaking;

    float2 centered = uv - float2(0.5);
    float dist = length(centered);
    float falloff = smoothstep(0.55, 0.2, dist);

    // Deep space background
    float3 bg = float3(0.01, 0.01, 0.04);

    // Grid of stars
    float2 gridUV = uv * 12.0;
    float2 cell = floor(gridUV);
    float2 local = fract(gridUV);

    float2 starOffset = float2(hash21c(cell), hash21c(cell + 0.5));
    float2 starPos = starOffset * 0.6 + 0.2;
    float starDist = length(local - starPos);

    float starBright = twinkle(cell, time, 1.0);

    float core = smoothstep(0.08, 0.01, starDist);
    float halo = smoothstep(0.25, 0.02, starDist) * 0.3;
    float star = (core + halo) * starBright;

    // Constellation lines — connect to nearby cells
    float lineGlow = 0.0;
    for (int dx = -1; dx <= 1; dx++) {
        for (int dy = -1; dy <= 1; dy++) {
            if (dx == 0 && dy == 0) continue;
            float2 neighbor = float2(dx, dy);
            float2 nCell = cell + neighbor;
            float2 nStarPos = float2(hash21c(nCell), hash21c(nCell + 0.5)) * 0.6 + 0.2;
            float2 nStarLocal = nStarPos + neighbor;
            float lineLen = length(nStarLocal - starPos);
            if (lineLen > 0.001) {
                float along = dot(local - starPos, normalize(nStarLocal - starPos));
                if (along > 0.0 && along < lineLen) {
                    float d = length(cross(float3(local - starPos, 0), float3(nStarLocal - starPos, 0))) / lineLen;
                    lineGlow += smoothstep(0.03, 0.005, d) * 0.15 * starBright;
                }
            }
        }
    }

    // Expression-driven star color
    float3 starColor;
    if (expression < 0.5)       starColor = float3(0.85, 0.9, 1.0);    // neutral
    else if (expression < 1.5)  starColor = float3(1.0, 0.9, 0.6);     // happy
    else if (expression < 2.5)  starColor = float3(0.4, 0.9, 1.0);     // curious
    else if (expression < 3.5)  starColor = float3(0.3, 0.4, 1.0);     // thinking
    else if (expression < 4.5)  starColor = float3(1.0, 1.0, 1.0);     // surprised
    else if (expression < 5.5)  starColor = float3(1.0, 0.7, 0.3);     // concerned
    else if (expression < 6.5)  starColor = float3(0.2, 1.0, 0.95);    // excited
    else                          starColor = float3(0.5, 0.3, 0.7);   // sleepy

    // ======== EYES (intensity > 0.2) — constellation ring eyes ========
    // Ring of stars around eye centers
    float2 leftEyeCenter  = float2(0.38, 0.73);
    float2 rightEyeCenter = float2(0.62, 0.73);

    // Outer ring of dots
    float leftRing  = 0.0;
    float rightRing = 0.0;
    for (int i = 0; i < 8; i++) {
        float angle = float(i) * 0.7854; // pi/4
        float2 dir = float2(cos(angle), sin(angle));
        leftRing  += circle(uv, leftEyeCenter  + dir * 0.065, 0.015);
        rightRing += circle(uv, rightEyeCenter + dir * 0.065, 0.015);
    }
    float eyes = max(leftRing, rightRing) * 0.5;

    // Bright central star pupil
    float leftPupil  = circle(uv, leftEyeCenter, 0.025);
    float rightPupil = circle(uv, rightEyeCenter, 0.025);
    float pupils = max(leftPupil, rightPupil);

    // Pupil twinkle
    float pupilTwinkle = 0.7 + 0.3 * sin(time * 2.0 + sin(time * 1.5));

    // Sleepy: ring fades and orbits slow
    float sleepyFactor = (expression > 6.5) ? 0.25 : 1.0;

    float3 ringColor = starColor;
    float3 pupilGlow = float3(1.0, 1.0, 0.85);

    // ======== MOUTH (isSpeaking > 0.5) — arc of small stars ========
    float mouthStars = 0.0;
    float mouthPhase = isSpeaking > 0.5 ? 0.5 + 0.5 * sin(time * 6.0) : 0.2;
    float mouthY = 0.28;
    for (int i = 0; i < 6; i++) {
        float t = (float(i) - 2.5) / 3.0; // -0.83 to +0.83
        float2 mouthCenter = float2(0.5 + t * 0.12, mouthY - abs(t) * 0.04 * mouthPhase);
        mouthStars += circle(uv, mouthCenter, 0.015) * (0.5 + 0.5 * sin(time * 4.0 + float(i)));
    }
    float3 mouthColor = float3(0.6, 0.7, 1.0);

    // ======== COMPOSITING ========
    float3 color = bg * (1.0 - falloff) + (star * starColor + lineGlow * starColor) * falloff * intensity;

    // Eyes overlaid
    if (intensity > 0.2) {
        color = mix(color, ringColor, eyes * falloff * intensity * 0.8 * sleepyFactor);
        color = mix(color, pupilGlow, pupils * falloff * intensity * 0.9 * pupilTwinkle * sleepyFactor);
    }

    // Mouth
    if (isSpeaking > 0.5) {
        color = mix(color, mouthColor, mouthStars * falloff * 0.85);
    }

    // Speaking: stars brighten
    float speakPulse = isSpeaking * (0.5 + 0.5 * sin(time * 8.0));
    color += speakPulse * starColor * 0.15 * falloff;

    // Opacity
    float opacity = falloff * intensity;
    if (intensity > 0.2) {
        opacity = max(opacity, (eyes + pupils) * intensity * 0.5);
    }
    if (isSpeaking > 0.5) {
        opacity = max(opacity, mouthStars * 0.6);
    }

    params.surface().set_base_color(half3(color));
    params.surface().set_opacity(half(opacity));
}
