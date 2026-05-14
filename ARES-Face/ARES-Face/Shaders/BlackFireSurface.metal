// BlackFireSurface.metal — Black fire surface shader (Phase 1)
// Dark violet/black body with hot white-violet core, procedural noise animation

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

using namespace metal;

constexpr sampler kSampler(coord::normalized, address::repeat, filter::linear);

// Procedural hash for noise
float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

// Value noise
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

// Fractional Brownian Motion for volumetric fire
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

[[stitchable]]
void blackFireSurface(realitykit::surface_parameters params,
                      constant SurfaceCustomUniforms &customParams) {
    float2 uv = params.geometry().uv0();
    float time = customParams.time;
    float intensity = customParams.intensity;
    float expression = customParams.expression;
    float isSpeaking = customParams.isSpeaking;
    
    // Distance from center for spherical falloff
    float2 centered = uv - float2(0.5);
    float dist = length(centered);
    float angle = atan2(centered.y, centered.x);
    
    // Animate UV upward for flame rise effect
    float2 flameUV = uv;
    flameUV.y += time * 0.3;  // Slow upward scroll
    flameUV.x += sin(flameUV.y * 4.0 + time * 0.7) * 0.05;  // Slight horizontal sway
    
    // Multi-octave noise for volumetric fire
    // Large-scale turbulence
    float largeNoise = fbm(flameUV * 3.0 + float2(time * 0.2, time * 0.4));
    // Medium noise for detail
    float medNoise = vnoise(flameUV * 8.0 + float2(time * 0.5, -time * 0.3));
    // Fine detail
    float fineNoise = vnoise(flameUV * 16.0 + float2(-time * 0.8, time * 0.6));
    
    // Combine noise layers — fire-like pattern
    float firePattern = largeNoise * 0.6 + medNoise * 0.3 + fineNoise * 0.1;
    
    // Upward fade: fire is stronger at bottom, weaker at top
    float verticalFade = 1.0 - smoothstep(0.0, 0.6, uv.y);
    // Radial fade from center
    float radialFade = 1.0 - smoothstep(0.05, 0.5, dist);
    
    // Distortion by time — flicker
    float flicker = 0.9 + 0.1 * sin(time * 5.0 + sin(time * 13.0) * 0.5);
    
    // Combined fire factor
    float fire = firePattern * verticalFade * radialFade * flicker;
    fire = clamp(fire * intensity * 2.0, 0.0, 1.0);
    
    // Color palette — expression affects hue shift
    // Base: dark violet/black body → hot violet core → white-hot center
    float hueShift = 0.0;
    if (expression > 0.5 && expression < 1.5) {       // happy — warmer
        hueShift = 0.12;
    } else if (expression > 1.5 && expression < 2.5) { // curious — cyan tint
        hueShift = -0.08;
    } else if (expression > 2.5 && expression < 3.5) { // thinking — deep purple
        hueShift = 0.05;
    } else if (expression > 3.5 && expression < 4.5) { // surprised — bright
        hueShift = 0.0;
    } else if (expression > 4.5 && expression < 5.5) { // concerned — blue
        hueShift = -0.15;
    } else if (expression > 5.5 && expression < 6.5) { // excited — magenta
        hueShift = 0.2;
    } else if (expression > 6.5) {                      // sleepy — dim blue
        hueShift = -0.2;
    }
    
    // Core color — white-hot at very high fire levels
    float3 hotCore = float3(0.85 + hueShift * 0.3, 0.75, 1.0);  // White-violet
    float3 midGlow  = float3(0.5 + hueShift * 0.5, 0.2, 0.85);   // Bright violet  
    float3 bodyColor = float3(0.15 + hueShift * 0.3, 0.02, 0.35); // Dark violet
    float3 outerColor = float3(0.05 + hueShift * 0.1, 0.01, 0.18);// Near-black
    
    // Mix colors based on fire intensity
    float3 color;
    if (fire > 0.75) {
        color = mix(midGlow, hotCore, (fire - 0.75) / 0.25);
    } else if (fire > 0.4) {
        color = mix(bodyColor, midGlow, (fire - 0.4) / 0.35);
    } else if (fire > 0.1) {
        color = mix(outerColor, bodyColor, (fire - 0.1) / 0.3);
    } else {
        color = outerColor * (fire / 0.1);
    }
    
    // Add ember sparks — bright points that float through the fire
    float sparkPhase = fract(sin(dot(uv * 50.0, float2(12.9898, 78.233))) * 43758.5453);
    float sparkTime = fract(time * 0.5 + sparkPhase * 6.28);
    float spark = smoothstep(0.97, 1.0, sparkPhase) * smoothstep(0.0, 0.1, sparkTime) * smoothstep(0.5, 0.1, sparkTime);
    float3 sparkColor = float3(0.7, 0.5, 1.0);
    color = mix(color, sparkColor, spark * intensity * 0.5);
    
    // Speaking modulation — slight brightness pulse
    if (isSpeaking > 0.5) {
        float speakPulse = 0.85 + 0.15 * sin(time * 8.0);
        color *= speakPulse;
    }

    // Cognition-driven uniforms (Phase 4 bindings).
    // emissivePulse brightens the core when ARES is confident; glitchAmplitude
    // adds a brief pixel-jump when error count climbs. Both clamped via the
    // CognitiveBindings table on the Swift side so no per-shader guarding.
    color *= (0.85 + 0.3 * customParams.emissivePulse);
    if (customParams.glitchAmplitude > 0.0) {
        float glitch = hash21(uv * 80.0 + float2(time * 17.0)) - 0.5;
        color += float3(glitch) * customParams.glitchAmplitude * 0.4;
    }
    
    // Final opacity — fade out edges smoothly
    float opacity = intensity * smoothstep(0.55, 0.1, dist) * flicker;
    opacity = clamp(opacity * 1.5, 0.0, 1.0);
    
    // Ensure minimal visibility at idle
    if (intensity < 0.1) {
        opacity = max(opacity, 0.03);
        color = float3(0.05, 0.01, 0.12);
    }
    
    params.surface().set_base_color(half3(color));
    params.surface().set_opacity(half(opacity));
}