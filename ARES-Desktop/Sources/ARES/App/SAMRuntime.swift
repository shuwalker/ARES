import Foundation
import SwiftUI
import ConversationEngine
import APIFramework
import ConfigurationSystem

/// Bootstraps SAM's conversation runtime as a Hermes-connected provider inside ARES.
/// This gives ARES SAM-quality chat without running SAM standalone.
@MainActor
final class SAMRuntime: ObservableObject {
    @Published var conversationManager: ConversationManager
    @Published var endpointManager: EndpointManager
    @Published var sharedConversationService: SharedConversationService

    private static let hermesBaseURL = "http://localhost:8642/v1"
    private static let hermesAPIKey = "2e7f9a3b4c5d6e8f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e4f"
    private static let hermesModel = "hermes-agent"

    init() {
        let cm = ConversationManager()
        self.conversationManager = cm

        let em = EndpointManager(conversationManager: cm)
        self.endpointManager = em

        let scs = SharedConversationService(conversationManager: cm)
        self.sharedConversationService = scs

        cm.injectAIProvider(em)
        cm.injectSystemPromptManager(SystemPromptManager.shared)
        scs.injectEndpointManager(em)

        // Configure Hermes as the custom provider
        configureHermesProvider()
    }

    private func configureHermesProvider() {
        let config = ProviderConfiguration(
            providerId: "hermes-agent",
            providerType: .custom,
            isEnabled: true,
            apiKey: Self.hermesAPIKey,
            baseURL: Self.hermesBaseURL,
            models: [Self.hermesModel],
            maxTokens: 8192,
            temperature: 0.7,
            customHeaders: nil,
            timeoutSeconds: 300,
            retryCount: 3
        )

        do {
            let data = try JSONEncoder().encode(config)
            UserDefaults.standard.set(data, forKey: "provider_config_hermes-agent")
        } catch {
            print("[SAMRuntime] Failed to encode Hermes provider config: \(error)")
        }

        endpointManager.reloadProviderConfigurations()
        
        // Default ChatWidget to Hermes — prevents it trying gpt-4
        UserDefaults.standard.set(Self.hermesModel, forKey: "defaultModel")
        
        print("[SAMRuntime] Hermes provider configured — \(Self.hermesBaseURL)")
    }

    /// Create a new conversation with Hermes ready to go.
    func createConversation() -> ConversationMessageBus? {
        conversationManager.createNewConversation()
        guard let conv = conversationManager.activeConversation else {
            print("[SAMRuntime] No active conversation after create")
            return nil
        }
        return conv.messageBus
    }
}
