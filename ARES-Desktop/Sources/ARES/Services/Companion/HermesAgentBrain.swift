import Foundation
import ARESCore

final class HermesAgentBrain: ReasoningBrain, @unchecked Sendable {
    let capabilities: Set<String> = ["respond", "streaming", "memory", "tools", "planning", "reflection"]
    
    private let hermesBaseURL: String
    
    init(hermesURL: String = "http://localhost:8642") {
        self.hermesBaseURL = hermesURL
    }
    
    func plan(context: SceneUnderstanding) async throws -> [AgentTask] {
        // Ask Hermes to generate a plan based on the scene understanding.
        // Serializes the scene graph and sends it to the chat endpoint.
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
                onToken: nil
            )
            
            let tasks = parseTaskList(from: result.responseText)
            print("✅ [HermesAgentBrain] Plan generated: \(tasks.count) tasks")
            return tasks
        } catch {
            print("⚠️  [HermesAgentBrain] Planning failed: \(error.localizedDescription)")
            return []
        }
    }
    
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
            onToken: { partial, isFinished in
                onToken?(partial, isFinished)
            }
        )
        return result.responseText
    }
    
    func reflect(on experience: Experience) async throws {
        // Send the experience to the reasoning engine for reflection.
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
                onToken: nil
            )
            
            if !result.responseText.isEmpty {
                print("✅ [HermesAgentBrain] Reflection complete: \(String(result.responseText.prefix(200)))")
                
                // Store reflection in memory for future retrieval
                if let sqliteMemory = CompanionChatService.shared.currentMemoryStore as? SQLiteMemoryStore {
                    try? await sqliteMemory.store(key: "reflection:\(experience.taskId)", value: AnyCodable.string(result.responseText))
                }
            }
        } catch {
            print("⚠️  [HermesAgentBrain] Reflection failed: \(error.localizedDescription)")
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