#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// Embodiment protocol: defines what a body can do.
/// Conforming types: DesktopEmbodiment, RobotEmbodiment, WatchEmbodiment, etc.
///
/// Design rule (from Lilith): Adding a method here is an architectural change.
/// Do it deliberately. Layer 1 (brain) must not import concrete embodiments,
/// only this protocol.
public protocol Embodiment: AnyObject, Sendable {
    /// Current state: idle, listening, thinking, speaking, sleeping.
    var state: EmbodimentState { get async }

    /// What this body can do. Used for capability gating at boot.
    /// Examples: ["expression", "gaze", "speech", "arms", "wheels"]
    var capabilities: Set<String> { get }

    /// Body kind. Used to select implementations.
    /// Examples: "desktop", "robot", "watch", "humanoid"
    var kind: String { get }

    /// Set face expression (emotion + intensity).
    /// Throws if this embodiment doesn't have "expression" capability.
    func setFaceExpression(_ expr: FaceExpression) async throws

    /// Set eye gaze direction (look at point, duration in seconds).
    /// Throws if this embodiment doesn't have "gaze" capability.
    func setEyeGaze(_ target: EyeGazeTarget) async throws

    /// Speak text with prosody controls (pitch, rate, energy).
    /// Throws if this embodiment doesn't have "speech" capability.
    func speak(text: String, prosody: Prosody) async throws

    /// Request approval for a high-risk action.
    /// UI may show confirmation dialog.
    /// Returns true if approved, false if denied or timed out.
    func requestApproval(_ action: ApprovalRequest) async throws -> Bool

    /// Get metadata about a capability.
    /// Examples: getCapabilityInfo("arms") → {"count": 2, "dof": 7, "gripper": true}
    func getCapabilityInfo(name: String) -> [String: AnyCodable]?
}

/// Current state of the embodiment's presence.
public enum EmbodimentState: String, Codable, Sendable {
    case idle      // Neutral expression, no active listening
    case listening // Attending to input; ears up
    case thinking  // Processing; eyes focused inward
    case speaking  // Actively speaking
    case sleeping  // Low power; eyes closed
}

/// Face expression: emotion + intensity + animation flags.
public struct FaceExpression: Codable, Sendable, Equatable {
    public let emotion: String      // "happy", "sad", "confused", "thinking", etc.
    public let intensity: Double    // 0.0 (none) ... 1.0 (maximum)
    public let blinking: Bool       // Override blink animation

    public init(emotion: String, intensity: Double = 0.5, blinking: Bool = true) {
        self.emotion = emotion
        self.intensity = max(0, min(1, intensity))
        self.blinking = blinking
    }
}

/// Eye gaze target.
public struct EyeGazeTarget: Codable, Sendable, Equatable {
    public let point: CGPoint       // (x, y) in screen coords or 3D space
    public let duration: TimeInterval

    public init(point: CGPoint, duration: TimeInterval = 0.5) {
        self.point = point
        self.duration = max(0, duration)
    }
}

/// Approval request: used by brain to ask embodiment for permission.
public struct ApprovalRequest: Codable, Sendable {
    public let action: String
    public let impact: ApprovalImpact
    public let requiredCapabilities: Set<String>
    public let timeout: TimeInterval

    public enum ApprovalImpact: String, Codable, Sendable {
        case informational       // Just inform user
        case confirmRequired     // User must click OK
        case riskMitigation      // Risky action; show full warning
    }

    public init(
        action: String,
        impact: ApprovalImpact,
        requiredCapabilities: Set<String> = [],
        timeout: TimeInterval = 30
    ) {
        self.action = action
        self.impact = impact
        self.requiredCapabilities = requiredCapabilities
        self.timeout = timeout
    }
}
