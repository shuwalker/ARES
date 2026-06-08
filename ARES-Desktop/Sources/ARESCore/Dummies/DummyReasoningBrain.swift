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

    public func respond(to input: String, context: ConversationContext) async throws -> String {
        print("🤖 [DUMMY] Responding to: '\(input)'")
        return "🤖 Echo: \(input)"
    }

    public func reflect(on experience: Experience) async throws {
        print("🤖 [DUMMY] Reflecting on: \(experience.taskId) → \(experience.outcome)")
    }
}
