import Foundation

/// No-op Embodiment for testing and rapid iteration.
/// Prints actions to console instead of rendering.
public final class DummyEmbodiment: Embodiment, @unchecked Sendable {
    private var _state: EmbodimentState = .idle

    public let capabilities: Set<String> = ["expression", "gaze", "speech", "approval"]
    public let kind: String = "dummy"

    public var state: EmbodimentState {
        get async { _state }
    }

    public init() {}

    public func setFaceExpression(_ expr: FaceExpression) async throws {
        _state = .thinking
        print("🤖 [DUMMY] Expression: \(expr.emotion) @ \(Int(expr.intensity * 100))%")
    }

    public func setEyeGaze(_ target: EyeGazeTarget) async throws {
        print("🤖 [DUMMY] Gaze: (\(Int(target.point.x)), \(Int(target.point.y))) over \(String(format: "%.1f", target.duration))s")
    }

    public func speak(text: String, prosody: Prosody) async throws {
        _state = .speaking
        print("🤖 [DUMMY] Speaking: \(text)")
        try? await Task.sleep(nanoseconds: 500_000_000)
        _state = .idle
    }

    public func requestApproval(_ action: ApprovalRequest) async throws -> Bool {
        print("🤖 [DUMMY] Approval request: \(action.action) [\(action.impact.rawValue)]")
        return true
    }

    nonisolated public func getCapabilityInfo(name: String) -> [String: AnyCodable]? {
        switch name {
        case "expression":
            return ["emotions": AnyCodable.string("happy, sad, thinking, confused")]
        case "gaze":
            return ["range": AnyCodable.string("360 degrees")]
        case "speech":
            return ["maxDuration": AnyCodable.number(120)]
        case "approval":
            return ["timeout": AnyCodable.number(30)]
        default:
            return nil
        }
    }
}
