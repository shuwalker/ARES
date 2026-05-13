import Foundation

// Declarative mapping from CognitiveSnapshot fields to shader uniform values.
//
// To bind a new cognition metric to a shader uniform:
//   1. Add a field to CognitiveUniformValues below.
//   2. Implement it in `CognitiveBindings.evaluate` (one line each).
//   3. Add a matching field in SharedHeader.h and AvatarRenderer.swift.
//   4. Reference the new uniform in whatever .metal shader needs it.
//
// Nothing else has to change. Shaders that don't reference the new uniform
// keep working unchanged.

struct CognitiveUniformValues {
    var noiseScale: Float
    var emissivePulse: Float
    var vertexJitter: Float
    var glitchAmplitude: Float

    static let neutral = CognitiveUniformValues(
        noiseScale: 0.3,
        emissivePulse: 0.5,
        vertexJitter: 0.0,
        glitchAmplitude: 0.0
    )
}

enum CognitiveBindings {
    /// Map a CognitiveSnapshot into the four uniform values the shader
    /// uniform struct exposes. Pure function — no side effects, easy to
    /// reason about and (eventually) unit-test in a separate target.
    static func evaluate(_ snapshot: CognitiveSnapshot, time: Float) -> CognitiveUniformValues {
        let urgency = urgencyToFloat(snapshot.loop.urgency)
        let depth = Float(min(snapshot.thought?.depth ?? 0, 10)) / 10.0
        let confidence = Float(snapshot.thought?.confidence ?? 0.5)
        let errorAmp = min(Float(snapshot.errors.count) / 5.0, 1.0)

        // Confidence and urgency both pulse, but at different rates and
        // intensities. Confidence is steady-state; urgency adds a faster
        // wobble when ARES is in a hurry.
        let basePulse = clamp(confidence, 0, 1)
        let urgencyPulse = urgency * (0.5 + 0.5 * sinf(time * 4.0))

        return CognitiveUniformValues(
            noiseScale: clamp(0.2 + urgency * 0.8, 0, 1),
            emissivePulse: clamp(basePulse + urgencyPulse * 0.25, 0, 1),
            vertexJitter: depth,
            glitchAmplitude: errorAmp
        )
    }

    private static func urgencyToFloat(_ urgency: String) -> Float {
        switch urgency.lowercased() {
        case "high":   return 1.0
        case "medium": return 0.5
        case "low":    return 0.15
        default:       return 0.15
        }
    }

    private static func clamp(_ v: Float, _ lo: Float, _ hi: Float) -> Float {
        return min(max(v, lo), hi)
    }
}
