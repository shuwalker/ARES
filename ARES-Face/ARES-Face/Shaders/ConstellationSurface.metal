// ConstellationSurface.metal — Star map with twinkling points, connecting lines, deep space

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

using namespace metal;

// Hash for star positions
float hash21c(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Star twinkle
float twinkle(float2 uv, float time, float seed) {
    float phase = hash21c(uv + seed) * 6.2831;
    float speed = 1.0 + hash21c(uv * 2.0 + seed) * 3.0;
    float t = sin(time * speed + phase) * 0.5 + 0.5;
    return t * t;  // sharper twinkle
}

[[stitchable]]
void constellationSurface(realitykit::surface_parameters params,
                          constant SurfaceCustomUniforms &customParams) {
    float2 uv = params.geometry().uv0();
    float time = customParams.time;
    float intensity = customParams.intensity;
    float expression = customParams.expression;
    float isSpeaking = customParams.isSpeaking;

    // Deep space background — slightly bluish black
    float3 bg = float3(0.01, 0.01, 0.04);

    // Distance from center for spherical falloff
    float2 centered = uv - float2(0.5);
    float dist = length(centered);
    float falloff = smoothstep(0.55, 0.2, dist);

    // Grid of stars
    float2 gridUV = uv * 12.0;  // 12x12 star grid
    float2 cell = floor(gridUV);
    float2 local = fract(gridUV);

    // Each cell has one star at a random position
    float2 starOffset = float2(hash21c(cell), hash21c(cell + 0.5));
    float2 starPos = starOffset * 0.6 + 0.2;  // keep within cell
    float starDist = length(local - starPos);

    // Star brightness — twinkle with time
    float starBright = twinkle(cell, time, 1.0);

    // Star glow — sharp core + soft halo
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

            // Transform neighbor star position to local grid space
            float2 nStarLocal = nStarPos + neighbor - (local - starOffset + starOffset);
            float lineDist = length(cross(float3(local - starPos, 0), float3(nStarLocal - starPos, 0)));
            float lineLen = length(nStarLocal - starPos);
            if (lineLen > 0.001) {
                float d = abs(dot(local - starPos, normalize(nStarLocal - starPos)));
                float along = dot(local - starPos, normalize(nStarLocal - starPos));
                if (along > 0.0 && along < lineLen) {
                    lineGlow += smoothstep(0.03, 0.005, d) * 0.15 * starBright;
                }
            }
        }
    }

    // Expression-driven color temperature
    // 0=neutral(white-blue), 1=happy(warm gold), 2=curious(cyan), 3=thinking(deep blue),
    // 4=surprised(bright white), 5=concerned(amber), 6=excited(electric cyan), 7=sleepy(dim violet)
    float3 starColor;
    if (expression < 0.5) {
        starColor = float3(0.85, 0.9, 1.0);  // neutral: white-blue
    } else if (expression < 1.5) {
        starColor = float3(1.0, 0.9, 0.6);   // happy: warm gold
    } else if (expression < 2.5) {
        starColor = float3(0.4, 0.9, 1.0);   // curious: cyan
    } else if (expression < 3.5) {
        starColor = float3(0.3, 0.4, 1.0);   // thinking: deep blue
    } else if (expression < 4.5) {
        starColor = float3(1.0, 1.0, 1.0);   // surprised: bright white
    } else if (expression < 5.5) {
        starColor = float3(1.0, 0.7, 0.3);   // concerned: amber
    } else if (expression < 6.5) {
        starColor = float3(0.2, 1.0, 0.95);  // excited: electric cyan
    } else {
        starColor = float3(0.5, 0.3, 0.7);   // sleepy: dim violet
    }

    // Speaking pulse — stars brighten and twinkle faster
    float speakPulse = isSpeaking * (0.5 + 0.5 * sin(time * 8.0));

    // Compose: background + stars + constellation lines
    float3 color = bg * (1.0 - falloff) + (star * starColor + lineGlow * starColor) * falloff * intensity;
    color += speakPulse * starColor * 0.15 * falloff;  // speaking glow

    // Opacity: sphere falloff + intensity-driven visibility
    float opacity = falloff * intensity;

    params.surface().set_base_color(half3(color));
    params.surface().set_opacity(half(opacity));
}