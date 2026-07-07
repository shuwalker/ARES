import Foundation

/// Synthetic mimicry: generates expression animations.
public final class DummyMimicry: Mimicry, @unchecked Sendable {
    private var _enabled = true
    private var _realism = 0.5

    public let capabilities: Set<String> = ["expressions", "gaze", "blinking"]

    public init() {
        print("🤖 [DUMMY] Mimicry: initialized")
    }

    public var mimicryStream: AsyncStream<MimicryFrame> {
        AsyncStream { continuation in
            Task {
                let emotions = ["neutral", "happy", "curious", "thinking"]
                var index = 0
                while true {
                    let emotion = emotions[index % emotions.count]
                    let frame = MimicryFrame(
                        expression: FaceExpression(emotion: emotion, intensity: 0.5),
                        eyeGaze: EyeGazeTarget(point: CGPoint(x: CGFloat.random(in: 0...512), y: CGFloat.random(in: 0...512))),
                        confidence: 0.9,
                        isBlinking: index % 10 == 0
                    )
                    continuation.yield(frame)
                    index += 1
                    try? await Task.sleep(nanoseconds: 33_000_000)  // 30fps
                }
            }
        }
    }

    public func setRealism(_ level: Double) async throws {
        _realism = max(0, min(1, level))
        print("🤖 [DUMMY] Mimicry realism → \(Int(_realism * 100))%")
    }

    public func setEnabled(_ enabled: Bool) async throws {
        _enabled = enabled
        print("🤖 [DUMMY] Mimicry \(enabled ? "enabled" : "disabled")")
    }
}
