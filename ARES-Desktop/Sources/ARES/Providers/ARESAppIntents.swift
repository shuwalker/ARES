import AppIntents
import SwiftUI
import ARESCore

/// Root AppIntents package for ARES
public struct ARESShortcuts: AppShortcutsProvider {
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ChatWithARESIntent(),
            phrases: [
                "Ask ARES \(\.$message)",
                "Chat with ARES",
                "Tell ARES to \(\.$message)"
            ],
            shortTitle: "Chat with ARES",
            systemImageName: "message.fill"
        )
    }
}

/// The AppIntent to talk to ARES
public struct ChatWithARESIntent: AppIntent {
    public static let title: LocalizedStringResource = "Ask ARES"
    public static let description: IntentDescription = "Send a message to ARES and get a response."

    @Parameter(title: "Message", description: "The message to send to ARES", requestValueDialog: "What do you want to ask ARES?")
    public var message: String

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let service = CompanionChatService.shared
        
        // Use the gateway configured in the service to send the message
        // Since Intents run in the background or separately, we can use the non-streaming fallback
        let config = CompanionConfig.load()
        let result = try await service.sendMessage(
            message,
            sessionID: "intent-\(UUID().uuidString.prefix(8))",
            model: config.model,
            provider: config.provider
        )
        
        // Also persist this turn to SwiftData!
        try? service.persistSession(
            turns: [
                CompanionChatService.PersistedTurn(role: "user", content: message, timestamp: Date()),
                CompanionChatService.PersistedTurn(role: "assistant", content: result.responseText, timestamp: Date())
            ],
            sessionID: result.sessionID,
            model: config.model
        )
        
        return .result(value: result.responseText)
    }
}
