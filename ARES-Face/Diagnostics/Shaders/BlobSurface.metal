// BlobSurface.metal — Soft metaball organism with glowing eyes and squishy mouth

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

// Elliptical distance for organic eye shape
float blobEye(float2 uv, float2 center, float rx, float ry) {
    float2 d = (uv - center) / float2(rx, ry);
    return smoothstep(1.0, 0.6, dot(d, d));
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
    if (expression > 0.5 && expression < 1.5)       hue = 0.18;   // happy
    else if (expression > 1.5 && expression < 2.5)  hue = 0.28;   // curious
    else if (expression > 2.5 && expression < 3.5)  hue = 0.05;   // thinking
    else if (expression > 3.5 && expression < 4.5)  hue = 0.12;   // surprised
    else if (expression > 4.5 && expression < 5.5)  hue = 0.72;   // concerned
    else if (expression > 5.5 && expression < 6.5)  hue = 0.95;   // excited
    else if (expression > 6.5)                       hue = 0.60;  // sleepy

    float3 coreColor = hsv2rgb(float3(hue, 0.65, 0.95));
    float3 midColor  = hsv2rgb(float3(hue + 0.04, 0.75, 0.55));
    float3 edgeColor = hsv2rgb(float3(hue - 0.03, 0.85, 0.25));

    // Soft glow edges
    float sdfLike = smoothstep(0.0, 1.0, combinedNoise);
    float edgeGlow = smoothstep(0.55, 0.15, dist + (1.0 - sdfLike) * 0.3);
    float coreGlow = smoothstep(0.45, 0.0, dist - sdfLike * 0.2);

    float3 color = mix(edgeColor, midColor, edgeGlow);
    color = mix(color, coreColor, coreGlow);

    // ======== EYES (intensity > 0.2) — glowing organic eyes ========
    float leftEye  = blobEye(uv, float2(0.38, 0.75), 0.07, 0.10);
    float rightEye = blobEye(uv, float2(0.62, 0.75), 0.07, 0.10);
    float eyes = max(leftEye, rightEye);

    // Inner glow pupil
    float leftGlow  = blobEye(uv, float2(0.38, 0.75), 0.03, 0.05);
    float rightGlow = blobEye(uv, float2(0.62, 0.75), 0.03, 0.05);
    float glowPupils = max(leftGlow, rightGlow);

    // Eye expression — eyes narrow when sleepy
    float sleepyMask = (expression > 6.5) ? smoothstep(0.76, 0.72, uv.y) : 0.0;

    float3 eyeGlowColor = hsv2rgb(float3(hue + 0.12, 0.4, 1.0));
    float3 pupilColor = hsv2rgb(float3(hue + 0.08, 0.9, 0.08));

    // ======== MOUTH (isSpeaking > 0.5) — squishy organic mouth ========
    // Oval mouth that pulses with speech
    float2 mouthUV = uv - float2(0.5, 0.3);
    float mouthPhase = isSpeaking > 0.5 ? 0.5 + 0.5 * sin(time * 5.0 + sin(time * 3.5)) : 0.3;
    float mouthWidth = 0.15;
    float mouthHeight = 0.025 * mouthPhase;
    float mouthD = (mouthUV.x * mouthUV.x) / (mouthWidth * mouthWidth) +
                   (mouthUV.y * mouthUV.y) / max(mouthHeight * mouthHeight, 0.0001);
    float mouth = smoothstep(1.0, 0.7, mouthD);

    // Inner mouth darker
    float innerMouthD = (mouthUV.x * mouthUV.x) / ((mouthWidth - 0.03) * (mouthWidth - 0.03)) +
                        (mouthUV.y * mouthUV.y) / max((mouthHeight - 0.005) * (mouthHeight - 0.005), 0.0001);
    float innerMouth = smoothstep(1.0, 0.7, innerMouthD);

    float3 mouthOuter = hsv2rgb(float3(hue + 0.06, 0.7, 0.15));
    float3 mouthInner = float3(0.02, 0.0, 0.0);

    // ======== COMPOSITING ========
    if (intensity > 0.2) {
        // Glowing eye whites
        color = mix(color, eyeGlowColor, eyes * 0.9);
        // Dark pupils
        color = mix(color, pupilColor, glowPupils * 0.85);
        // Sleepy eyelids
        color = mix(color, edgeColor * 0.3, sleepyMask * eyes);
    }

    // Speaking: pulsing core brightness + mouth
    if (isSpeaking > 0.5) {
        float speakPulse = 0.85 + 0.15 * sin(time * 4.0);
        color *= speakPulse;
        // Mouth
        color = mix(color, mouthOuter, mouth * 0.8);
        color = mix(color, mouthInner, innerMouth * 0.8);
    }

    // Opacity
    float opacity = intensity * edgeGlow * 0.9 + coreGlow * intensity * 0.1;
    if (intensity > 0.2) {
        opacity = max(opacity, eyes * intensity * 0.6);
    }
    opacity = clamp(opacity * 1.2, 0.0, 1.0);

    params.surface().set_base_color(half3(color));
    params.surface().set_opacity(half(opacity));
}
