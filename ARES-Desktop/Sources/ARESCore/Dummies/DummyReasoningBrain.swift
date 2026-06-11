import Foundation

/// No-op ReasoningBrain for testing. Echoes inputs.
public final class DummyReasoningBrain: ReasoningBrain, @unchecked Sendable {
    public nonisolated let capabilities: Set<String> = ["respond"]

    public init() {}

    public func plan(context: SceneUnderstanding) async throws -> [AgentTask] {
        print("🤖 [DUMMY] Planning with \(context.objects.count) objects")
        return [
            AgentTask(
                description: "Observe surroundings",
                requiredCapabilities: []
            ),
            AgentTask(
                description: "Report findings",
                requiredCapabilities: ["speech"]
            )
        ]
    }

    public func respond(
        to input: String,
        context: ConversationContext,
        onToken: (@Sendable (_ partial: String, _ isFinished: Bool) -> Void)? = nil
    ) async throws -> String {
        print("🤖 [DUMMY] Responding to: \(input)")
        let reply = "Echo: \(input)"
        if let onToken = onToken {
            onToken(reply, true)
        }
        return reply
    }

    public func reflect(on experience: Experience) async throws {
        print("🤖 [DUMMY] Reflecting on: \(experience.taskId) → \(experience.outcome)")
    }
}
