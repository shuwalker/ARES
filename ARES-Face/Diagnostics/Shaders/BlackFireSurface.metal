// BlackFireSurface.metal — Dark fire avatar shader v2
// 3D volumetric fire with depth, chaotic turbulence, fast flicker
// No water ripples — sharp-edged combustion patterns

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

using namespace metal;

constexpr sampler kSampler(coord::normalized, address::repeat, filter::linear);

// Hash-based noise — sharp, not smooth
float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Gradient noise — sharper transitions than value noise
float gnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f); // smoothstep for continuity
    
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Turbulence — abs(noise) for sharp ridge-like fire patterns
float turbulence(float2 p, int octaves) {
    float value = 0.0;
    float amplitude = 1.0;
    float frequency = 1.0;
    for (int i = 0; i < octaves; i++) {
        value += amplitude * abs(gnoise(p * frequency) - 0.5) * 2.0;
        frequency *= 2.17; // Non-power-of-2 avoids regular patterns
        amplitude *= 0.55;
    }
    return value;
}

// Sharp fire noise — uses turbulence inversion for bright tongues
float fireNoise(float2 p, float time) {
    // Base: upward-scrolling turbulence with fast horizontal distortion
    float2 distort = float2(
        gnoise(p * 1.5 + float2(time * 0.8, time * 0.3)) * 0.4,
        gnoise(p * 1.5 + float2(time * 0.5, -time * 0.6)) * 0.3
    );
    
    // Fast upward scroll — fire rises quickly
    float2 scrollUV = p + distort;
    scrollUV.y -= time * 1.8; // Fast upward, not slow
    
    // Turbulence inversion: bright ridges = fire tongues
    float turb = turbulence(scrollUV * 3.0, 5);
    float fire = 1.0 - turb; // Invert: bright where turbulence is LOW (between ridges)
    
    return clamp(fire, 0.0, 1.0);
}

[[stitchable]]
void blackFireSurface(realitykit::surface_parameters params,
                      constant SurfaceCustomUniforms &customParams) {
    float2 uv = params.geometry().uv0();
    float time = customParams.time;
    float intensity = customParams.intensity;
    float expression = customParams.expression;
    float isSpeaking = customParams.isSpeaking;
    
    // Spherical coordinates for 3D depth feel
    float2 centered = uv - float2(0.5);
    float dist = length(centered);
    float angle = atan2(centered.y, centered.x);
    
    // ── Fire layers ──
    // Layer 1: Core fire — fast rise, bright tongues
    float core = fireNoise(uv * 2.0, time);
    
    // Layer 2: Outer glow — slower, wider, dimmer
    float outer = fireNoise(uv * 1.2 + float2(time * 0.1, -time * 0.3), time * 0.7);
    
    // Layer 3: Ember detail — fast fine noise
    float ember = turbulence(uv * 8.0 + float2(time * 1.2, -time * 2.0), 3);
    
    // ── Compose fire shape ──
    // Vertical bias: fire stronger at bottom, rising upward
    float riseShape = smoothstep(1.0, 0.0, uv.y); // Strong at bottom
    
    // Radial falloff: brightest at center
    float radialShape = 1.0 - smoothstep(0.0, 0.45, dist);
    
    // Core intensity: combine layers
    float fire = core * 0.65 + outer * 0.25 + ember * 0.10;
    fire *= riseShape * radialShape;
    
    // ── Flicker — fast, chaotic, like real fire ──
    // Multiple frequency flicker (not a smooth sine wave)
    float flicker = 0.88
        + 0.07 * sin(time * 11.3 + sin(time * 23.7) * 0.8)
        + 0.05 * sin(time * 37.1 + cos(time * 7.3) * 1.5);
    
    fire = clamp(fire * intensity * 2.5 * flicker, 0.0, 1.0);
    
    // ── Color palette ──
    // Expression affects color temperature
    float hueShift = 0.0;
    if (expression > 0.5 && expression < 1.5) {       // happy — warm shift
        hueShift = 0.15;
    } else if (expression > 1.5 && expression < 2.5) { // curious — cyan tint
        hueShift = -0.08;
    } else if (expression > 2.5 && expression < 3.5) { // thinking — deeper purple
        hueShift = 0.05;
    } else if (expression > 3.5 && expression < 4.5) { // surprised — brighter
        hueShift = 0.10;
    } else if (expression > 4.5 && expression < 5.5) { // concerned — cool blue
        hueShift = -0.15;
    } else if (expression > 5.5 && expression < 6.5) { // excited — magenta
        hueShift = 0.22;
    } else if (expression > 6.5) {                      // sleepy — dim blue
        hueShift = -0.20;
    }
    
    // Fire color gradient: white-hot core → bright violet → dark body → near-black
    float3 whiteHot   = float3(0.95 + hueShift * 0.2, 0.90, 1.0);   // Near white with violet tint
    float3 brightCore = float3(0.65 + hueShift * 0.4, 0.25, 0.95);   // Bright violet-magenta
    float3 midFlame   = float3(0.30 + hueShift * 0.5, 0.08, 0.65);   // Medium purple
    float3 darkBody   = float3(0.10 + hueShift * 0.2, 0.02, 0.30);   // Dark violet
    float3 voidOuter  = float3(0.03 + hueShift * 0.05, 0.005, 0.12);  // Near black
    
    // Map fire intensity to color gradient
    float3 color;
    if (fire > 0.85) {
        color = mix(brightCore, whiteHot, (fire - 0.85) / 0.15);
    } else if (fire > 0.55) {
        color = mix(midFlame, brightCore, (fire - 0.55) / 0.30);
    } else if (fire > 0.25) {
        color = mix(darkBody, midFlame, (fire - 0.25) / 0.30);
    } else if (fire > 0.05) {
        color = mix(voidOuter, darkBody, (fire - 0.05) / 0.20);
    } else {
        color = voidOuter;
    }
    
    // ── Ember sparks — brief bright points that fade fast ──
    float sparkPhase = fract(sin(dot(uv * 80.0, float2(12.9898, 78.233))) * 43758.5453);
    // Sparks appear and die quickly — not slow lingering
    float sparkLife = fract(time * 3.0 + sparkPhase * 6.28);
    float spark = smoothstep(0.98, 1.0, sparkPhase) 
                * smoothstep(0.0, 0.03, sparkLife) 
                * smoothstep(0.15, 0.03, sparkLife); // Fast death
    float3 sparkColor = float3(0.9, 0.6, 1.0);
    color = mix(color, sparkColor, spark * intensity * 0.7);
    
    // ── Speaking modulation — rhythmic brightness pulse synced to voice ──
    if (isSpeaking > 0.5) {
        float speakPulse = 0.8 + 0.2 * sin(time * 12.0); // Fast flicker when speaking
        color *= speakPulse;
    }
    
    // ── Cognition uniforms ──
    color *= (0.85 + 0.3 * customParams.emissivePulse);
    if (customParams.glitchAmplitude > 0.0) {
        float glitch = hash21(uv * 120.0 + float2(time * 30.0)) - 0.5;
        color += float3(glitch) * customParams.glitchAmplitude * 0.4;
    }
    
    // ── Opacity: sharp edge, 3D depth ──
    // Use a steeper falloff for a crisper sphere edge — no soft "2D blob"
    float edgeFalloff = 1.0 - smoothstep(0.25, 0.48, dist);
    float opacity = intensity * edgeFalloff * flicker;
    opacity = clamp(opacity * 1.6, 0.0, 1.0);
    
    // Background glow — dim violet rim outside the sphere for 3D depth
    float rimGlow = smoothstep(0.48, 0.35, dist) * intensity * 0.15;
    color += float3(0.15, 0.05, 0.30) * rimGlow;
    
    // Minimum visibility at idle
    if (intensity < 0.1) {
        opacity = max(opacity, 0.04);
        color = float3(0.05, 0.01, 0.12);
    }
    
    params.surface().set_base_color(half3(color));
    params.surface().set_opacity(half(opacity));
}