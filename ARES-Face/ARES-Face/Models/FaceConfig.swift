import Foundation
import AppKit

/// Visual parameters per agent state, matching Python FaceConfig exactly.
/// These map to Metal shader uniforms.
struct FaceConfig: Codable {
    let state: AgentState
    let color: ColorRGB
    let opacity: Float
    let pulseSpeed: Float
    let pulseAmount: Float
    let pupilOffset: Offset2D
    
    // MARK: - Nested Types
    
    struct ColorRGB: Codable {
        let r: Float
        let g: Float
        let b: Float
    }
    
    struct Offset2D: Codable {
        let x: Float
        let y: Float
    }
    
    // MARK: - Intensity Computation
    
    /// Compute shader intensity from this config
    var intensity: Float {
        opacity * (1.0 + pulseAmount * 0.5)
    }
    
    // MARK: - Static Configs per State
    
    static let configs: [AgentState: FaceConfig] = [
        .idle: FaceConfig(
            state: .idle,
            color: ColorRGB(r: 0.10, g: 0.05, b: 0.25),
            opacity: 0.20,
            pulseSpeed: 0.5,
            pulseAmount: 0.05,
            pupilOffset: Offset2D(x: 0, y: 0)
        ),
        .awakened: FaceConfig(
            state: .awakened,
            color: ColorRGB(r: 0.30, g: 0.10, b: 0.55),
            opacity: 0.45,
            pulseSpeed: 1.0,
            pulseAmount: 0.12,
            pupilOffset: Offset2D(x: 0, y: -0.05)
        ),
        .listening: FaceConfig(
            state: .listening,
            color: ColorRGB(r: 0.20, g: 0.50, b: 0.70),
            opacity: 0.50,
            pulseSpeed: 1.5,
            pulseAmount: 0.08,
            pupilOffset: Offset2D(x: 0.1, y: 0)
        ),
        .thinking: FaceConfig(
            state: .thinking,
            color: ColorRGB(r: 0.55, g: 0.20, b: 0.85),
            opacity: 0.85,
            pulseSpeed: 2.0,
            pulseAmount: 0.18,
            pupilOffset: Offset2D(x: -0.05, y: -0.1)
        ),
        .speaking: FaceConfig(
            state: .speaking,
            color: ColorRGB(r: 0.40, g: 0.25, b: 0.95),
            opacity: 0.65,
            pulseSpeed: 3.0,
            pulseAmount: 0.25,
            pupilOffset: Offset2D(x: 0, y: 0.05)
        ),
        .sleeping: FaceConfig(
            state: .sleeping,
            color: ColorRGB(r: 0.05, g: 0.02, b: 0.15),
            opacity: 0.06,
            pulseSpeed: 0.3,
            pulseAmount: 0.02,
            pupilOffset: Offset2D(x: 0, y: 0)
        )
    ]
    
    static func config(for state: AgentState) -> FaceConfig {
        configs[state] ?? configs[.idle]!
    }
}