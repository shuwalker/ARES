import Foundation
import ARESCore
import os

// MARK: - GatewayBrain

/// A ReasoningBrain backed by an arbitrary GatewayProvider.
///
/// Unlike HermesAgentBrain (which always uses the CompanionChatService's
/// configured gateway), GatewayBrain carries its OWN gateway and optional
/// model, and routes every plan/respond/reflect call through them via the
/// service's per-call override parameters. This lets multiple brains coexist,
/// each bound to a different backend (Ollama, Claude, OpenAI, ...), while
/// still sharing the service's agent loop and tool routing.
final class GatewayBrain: ReasoningBrain, @unchecked Sendable {
    let capabilities: Set<String> = ["respond", "streaming", "tools", "planning", "reflection"]

    private let gateway: any GatewayProvider
    private let model: String?
    private let logger = Logger(subsystem: "com.ares", category: "GatewayBrain")

    init(gateway: any GatewayProvider, model: String? = nil) {
        self.gateway = gateway
        self.model = model
    }

    // MARK: - Planning

    func plan(context: SceneUnderstanding) async throws -> [AgentTask] {
        // Ask the backing gateway to generate a plan based on the scene
        // understanding. Serializes the scene graph into a prompt.
        let objectsDesc = context.objects.map { "\($0.kind) (\($0.id))" }.joined(separator: ", ")
        let relationsDesc = context.relationships.map { "\($0.subject) \($0.relation) \($0.object)" }.joined(separator: ", ")

        let planPrompt = """
        You are ARES, an autonomous AI assistant. Given the current scene understanding, generate a prioritized list of tasks to execute. Respond in JSON array format: [{"description": "...", "approvalRequired": false}]

        Objects observed: \(objectsDesc.isEmpty ? "none" : objectsDesc)
        Relationships: \(relationsDesc.isEmpty ? "none" : relationsDesc)
        Time: \(context.timestamp)
        """

        let messages = [GatewayMessage(role: "user", content: planPrompt)]

        do {
            let result = try await CompanionChatService.shared.sendMessageStream(
                messages: messages,
                sessionID: "ares-planning",
                gateway: gateway,
                modelOverride: model,
                onToken: { _, _ in }
            )

            let tasks = parseTaskList(from: result.responseText)
            logger.info("Plan generated via \(self.gateway.identifier, privacy: .public): \(tasks.count) tasks")
            return tasks
        } catch {
            logger.error("Planning failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    // MARK: - Responding

    func respond(
        to input: String,
        context: ConversationContext,
        onToken: (@Sendable (_ partial: String, _ isFinished: Bool) -> Void)? = nil
    ) async throws -> String {
        var gatewayMessages: [GatewayMessage] = []
        for msg in context.messages {
            let roleStr = msg.role == .user ? "user" : (msg.role == .assistant ? "assistant" : "system")
            gatewayMessages.append(GatewayMessage(role: roleStr, content: msg.content))
        }
        gatewayMessages.append(GatewayMessage(role: "user", content: input))

        let result = try await CompanionChatService.shared.sendMessageStream(
            messages: gatewayMessages,
            sessionID: context.sessionID,
            gateway: gateway,
            modelOverride: model,
            onToken: { partial, isFinished in
                onToken?(partial, isFinished)
            }
        )
        return result.responseText
    }

    // MARK: - Reflection

    func reflect(on experience: Experience) async throws {
        // Send the experience to the backing gateway for reflection.
        // The response feeds back into memory for future reasoning.
        let reflectPrompt = """
        You are ARES, reflecting on a recent experience to improve future performance. Briefly analyze:
        1. Task \(experience.taskId): \(experience.action)
        2. Outcome: \(experience.outcome)
        \(experience.feedback.map { "3. Feedback: \($0)" } ?? "3. No feedback recorded")

        In 2-3 sentences: what went well, what to improve, and what to remember.
        """

        let messages = [GatewayMessage(role: "user", content: reflectPrompt)]

        do {
            let result = try await CompanionChatService.shared.sendMessageStream(
                messages: messages,
                sessionID: "ares-reflection",
                gateway: gateway,
                modelOverride: model,
                onToken: { _, _ in }
            )

            if !result.responseText.isEmpty {
                logger.info("Reflection complete: \(String(result.responseText.prefix(200)), privacy: .public)")

                // Store reflection in memory for future retrieval
                if let store = await CompanionChatService.shared.currentMemoryStore {
                    let memory = Memory(
                        content: result.responseText,
                        context: ["type": AnyCodable.string("reflection"), "taskId": AnyCodable.string(experience.taskId)]
                    )
                    _ = try? await store.store(memory)
                }
            }
        } catch {
            logger.error("Reflection failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private helpers

    private func parseTaskList(from text: String) -> [AgentTask] {
        // Attempt JSON parsing first
        if let data = text.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return json.compactMap { item in
                guard let desc = item["description"] as? String else { return nil }
                let approvalRequired = item["approvalRequired"] as? Bool ?? false
                return AgentTask(description: desc, approvalRequired: approvalRequired)
            }
        }

        // Fallback: parse line-by-line
        let lines = text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.enumerated().map { index, line in
            let cleaned = line
                .replacingOccurrences(of: #"^\d+[\.\)]\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^[-•*]\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            return AgentTask(description: cleaned, approvalRequired: index == 0)
        }
    }
}
