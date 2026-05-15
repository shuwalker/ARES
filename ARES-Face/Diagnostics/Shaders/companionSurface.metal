// companionSurface.metal — Ball companion in glass dome: fuzzy dark sphere with single red slit-pupil eye and wide toothy grin, transforms between states
// Palette: body=#1A1A1A eye=#FF0000 teeth=#FFFFFF dome=#E0E0E0
// TODO: Full implementation — currently a minimal stub that renders a lit material

#include <metal_stdlib>
#include <RealityKit/RealityKit.h>
#include "SharedHeader.h"

using namespace metal;

[[nodiscard]]
fragment half4 companionSurface(
    RealityKit::SurfaceInput surface_input,
    RealityKit::Framebuffer fb,
    uint2 coord,
    RealityKit::SurfaceParameters params
) {
    // Stub: render with basic lighting and a tint based on expression
    half4 base = half4(0.5, 0.3, 0.7, 1.0); // placeholder purple
    float expr = params.uniforms().expression;
    float intensity = params.uniforms().intensity;
    float time = params.uniforms().time;
    
    // Pulse based on intensity
    half4 result = half4(base.rgb * (0.5 + 0.5 * intensity), base.a);
    return result;
}
