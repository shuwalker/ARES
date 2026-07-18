import Foundation

/// Mimicry protocol: avatar facial animation driven by user perception.
/// Distinct from Embodiment (which is *the body command interface*).
/// Mimicry is *reaction to perception* — landmark → expression mapping.
/// Conforming types: RealisticMimicry, ExpressionMimicry, DummyMimicry
public protocol Mimicry: AnyObject, Sendable {
    /// Subscribe to mimicry updates (expression + gaze driven by landmarks).
    /// Yields MimicryFrame at perception frame rate (~30fps).
    var mimicryStream: AsyncStream<MimicryFrame> { get }

    /// Update mimicry policy: how realistic vs stylized.
    /// 0.0 = perfect copy, 1.0 = fully stylized cartoon.
    func setRealism(_ level: Double) async throws

    /// Enable/disable mimicry (on → landmark→expression, off → neutral).
    func setEnabled(_ enabled: Bool) async throws

    /// What can this mimicry engine do?
    /// Examples: ["expressions", "gaze", "blinking", "micromovements"]
    var capabilities: Set<String> { get }
}

/// A single mimicry frame: the computed expression driven by landmarks.
public struct MimicryFrame: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let expression: FaceExpression        // Driven emotion + intensity
    public let eyeGaze: EyeGazeTarget           // Driven gaze direction
    public let confidence: Double                // 0...1 how confident the mimic is
    public let isBlinking: Bool                  // Blink state from landmarks

    public init(
        timestamp: Date = Date(),
        expression: FaceExpression,
        eyeGaze: EyeGazeTarget,
        confidence: Double = 1.0,
        isBlinking: Bool = false
    ) {
        self.timestamp = timestamp
        self.expression = expression
        self.eyeGaze = eyeGaze
        self.confidence = max(0, min(1, confidence))
        self.isBlinking = isBlinking
    }
}
