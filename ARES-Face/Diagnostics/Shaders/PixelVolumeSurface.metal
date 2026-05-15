// PixelVolumeSurface.metal — Voxel density with quantized grid blocks, LED pixel eyes, and block-matrix mouth

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

    float cellHash = hash21(gridUV * 3.7 + float2(1.337, 2.718));

    // Expression-driven base hue
    float hue = 0.15; // default amber voxel
    if (expression > 0.5 && expression < 1.5)       hue = 0.25;   // happy
    else if (expression > 1.5 && expression < 2.5)  hue = 0.45;   // curious
    else if (expression > 2.5 && expression < 3.5)  hue = 0.65;   // thinking
    else if (expression > 3.5 && expression < 4.5)  hue = 0.55;   // surprised
    else if (expression > 4.5 && expression < 5.5)  hue = 0.72;   // concerned
    else if (expression > 5.5 && expression < 6.5)  hue = 0.88;   // excited
    else if (expression > 6.5)                       hue = 0.60;  // sleepy

    float density = smoothstep(0.55, 0.0, dist) * (0.5 + cellHash * 0.5);
    float3 baseColor = hsv2rgb(float3(hue, 0.9, density));
    float3 edgeColor = hsv2rgb(float3(hue, 0.95, density * 0.25));

    // Grid edge detection for block outlines
    float2 fracUV = fract(uv * gridSize);
    float edge = smoothstep(0.0, 0.08, fracUV.x) * smoothstep(1.0, 0.92, fracUV.x) *
                 smoothstep(0.0, 0.08, fracUV.y) * smoothstep(1.0, 0.92, fracUV.y);

    float3 color = mix(edgeColor, baseColor, edge);

    // ======== EYES (intensity > 0.2) — LED pixel display eyes ========
    // Eye grid: 4x6 pixel blocks per eye
    float eyeGridSize = 28.0; // finer grid for eyes
    float2 eyeUV = fract(uv * eyeGridSize);
    float2 eyeCell = floor(uv * eyeGridSize);

    // Left eye region: 3x5 block grid centered at (0.38, 0.74)
    float2 leftEyeBlock = (uv - float2(0.38, 0.74)) * float2(1.5, 1.5);
    float leftEyeMask = smoothstep(0.09, 0.07, abs(leftEyeBlock.x)) *
                        smoothstep(0.12, 0.10, abs(leftEyeBlock.y));

    float2 rightEyeBlock = (uv - float2(0.62, 0.74)) * float2(1.5, 1.5);
    float rightEyeMask = smoothstep(0.09, 0.07, abs(rightEyeBlock.x)) *
                         smoothstep(0.12, 0.10, abs(rightEyeBlock.y));

    // LED pixel pattern — each sub-pixel cell randomly on/off
    float eyePixelHashL = hash21(eyeCell + float2(1.0, 2.0));
    float eyePixelHashR = hash21(eyeCell + float2(3.0, 4.0));
    float eyePixels = max(
        (leftEyeMask  > 0.1 ? step(0.4 + intensity * 0.3, eyePixelHashL) : 0.0),
        (rightEyeMask > 0.1 ? step(0.4 + intensity * 0.3, eyePixelHashR) : 0.0)
    );

    // Pupil — darker central block with occasional blink
    float blinkCycle = sin(time * 0.7 + sin(time * 0.3) * 0.5);
    float blink = smoothstep(0.85, 0.95, blinkCycle); // brief blinks

    float leftPupilBlock = (uv - float2(0.38, 0.74)) * float2(2.5, 2.5);
    float leftPupil = smoothstep(0.035, 0.03, abs(leftPupilBlock.x)) *
                      smoothstep(0.05, 0.045, abs(leftPupilBlock.y));
    float rightPupilBlock = (uv - float2(0.62, 0.74)) * float2(2.5, 2.5);
    float rightPupil = smoothstep(0.035, 0.03, abs(rightPupilBlock.x)) *
                       smoothstep(0.05, 0.045, abs(rightPupilBlock.y));
    float pupils = max(leftPupil, rightPupil) * (1.0 - blink);

    // Sleepy: pixel intensity dims
    float sleepyDim = (expression > 6.5) ? 0.3 : 1.0;

    float3 eyeLED = hsv2rgb(float3(hue + 0.15, 0.3, 1.0));
    float3 pupilDark = float3(0.01, 0.0, 0.02);

    // ======== MOUTH (isSpeaking > 0.5) — bar of LED blocks ========
    float mouthPhase = isSpeaking > 0.5 ? 0.6 + 0.4 * sin(time * 8.0 + sin(time * 5.0)) : 0.15;
    float mouthBarMask = smoothstep(0.03 * mouthPhase, 0.01 * mouthPhase,
                                    abs(uv.y - 0.28)) *
                         smoothstep(0.16, 0.14, abs(uv.x - 0.5));

    // Pixel LEDs in mouth bar
    float mouthCellHash = hash21(eyeCell + float2(5.0, 6.0));
    float mouthPixels = (mouthBarMask > 0.1) ?
        step(0.5 + mouthPhase * 0.3, mouthCellHash) : 0.0;

    float3 mouthLED = hsv2rgb(float3(hue + 0.2, 0.8, 0.8));
    float3 mouthOff = float3(0.02, 0.0, 0.01);

    // ======== COMPOSITING ========
    if (intensity > 0.2) {
        // Eye LED matrix
        color = mix(color, eyeLED, eyePixels * intensity * sleepyDim);
        color = mix(color, pupilDark, pupils * 0.9 * sleepyDim);
    }

    if (isSpeaking > 0.5) {
        color = mix(color, mouthLED, mouthPixels * 0.9);
        color = mix(color, mouthOff, (mouthBarMask - mouthPixels) * 0.7);
    }

    // Opacity
    float occupancy = step(0.35, density + cellHash * 0.15);
    float opacity = intensity * occupancy * edge;

    // Eyes boost opacity
    if (intensity > 0.2) {
        opacity = max(opacity, eyePixels * intensity * 0.7);
        opacity = max(opacity, pupils * 0.6);
    }
    if (isSpeaking > 0.5) {
        opacity = max(opacity, mouthPixels * 0.6);
    }

    opacity = clamp(opacity * 1.4, 0.0, 1.0);

    params.surface().set_base_color(half3(color));
    params.surface().set_opacity(half(opacity));
}
