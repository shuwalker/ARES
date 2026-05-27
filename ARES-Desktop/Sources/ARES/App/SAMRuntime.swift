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

    // Hermes provider connection.
    // Priority order: ARESAppState (user-configurable) → env var → hardcoded default.
    // ARES_HERMES_API_KEY must be supplied at launch; empty default means
    // requests go without auth (only valid against a local trusted Hermes).
    private static let hermesAPIKey = ProcessInfo.processInfo
        .environment["ARES_HERMES_API_KEY"] ?? ""

    /// Resolved at init-time from appState, which has already seeded UserDefaults
    /// before this object is constructed. This eliminates the gpt-4 race condition.
    private let resolvedBaseURL: String
    private let resolvedModel: String

    init(appState: ARESAppState? = nil) {
        // Resolve the gateway URL and model from appState first, then fall back
        // to env vars, then to hardcoded defaults.  appState.init() guarantees
        // UserDefaults["defaultModel"] is already written to "hermes-agent" (or the
        // user's persisted choice) before SAMRuntime is constructed, so ChatWidget's
        // @AppStorage("defaultModel") will never see "gpt-4" on a fresh launch.
        let envURL = ProcessInfo.processInfo.environment["ARES_HERMES_URL"]
        let envModel = ProcessInfo.processInfo.environment["ARES_HERMES_MODEL"]

        // Also check UserDefaults: ARESAppState.init() writes these before SAMRuntime
        // is constructed, so UserDefaults is a reliable pre-populated source.
        let udURL = UserDefaults.standard.string(forKey: "ARES.hermesGatewayURL")
        let udModel = UserDefaults.standard.string(forKey: "ARES.selectedModel")

        self.resolvedBaseURL = appState.map { "\($0.hermesGatewayURL)/v1" }
            ?? udURL.map { "\($0)/v1" }
            ?? envURL
            ?? "http://localhost:8642/v1"

        self.resolvedModel = appState?.selectedModel
            ?? udModel
            ?? envModel
            ?? "hermes-agent"

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
            baseURL: resolvedBaseURL,
            models: [resolvedModel],
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

        // Ensure defaultModel is set to the resolved model (belt-and-suspenders;
        // ARESAppState.init() already wrote this before we were constructed).
        UserDefaults.standard.set(resolvedModel, forKey: "defaultModel")

        print("[SAMRuntime] Hermes provider configured — \(resolvedBaseURL) model=\(resolvedModel)")
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
