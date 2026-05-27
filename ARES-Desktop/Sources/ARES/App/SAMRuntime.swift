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

    /// Persistent Companion-tab conversation. Lives on SAMRuntime so it survives
    /// tab switches (CompanionView gets torn down and recreated when the user
    /// switches tabs in ARESRootView).
    @Published var companionMessageBus: ConversationMessageBus?

    // Hermes provider connection. Resolved at init-time from appState/UserDefaults
    // so the gpt-4 race condition is eliminated. API key fallback chain:
    //   ARES_HERMES_API_KEY env var → UserDefaults["ARES.hermesAPIKey"] → empty
    // The Settings tab exposes the UserDefaults entry so the user can paste a key
    // without relaunching from a shell.
    private let resolvedBaseURL: String
    private let resolvedModel: String
    private let resolvedAPIKey: String

    init(appState: ARESAppState? = nil) {
        // Resolve the gateway URL and model from appState first, then fall back
        // to env vars, then to hardcoded defaults.  appState.init() guarantees
        // UserDefaults["defaultModel"] is already written to "hermes-agent" (or the
        // user's persisted choice) before SAMRuntime is constructed, so ChatWidget's
        // @AppStorage("defaultModel") will never see "gpt-4" on a fresh launch.
        let envURL = ProcessInfo.processInfo.environment["ARES_HERMES_URL"]
        let envModel = ProcessInfo.processInfo.environment["ARES_HERMES_MODEL"]
        let envKey = ProcessInfo.processInfo.environment["ARES_HERMES_API_KEY"]

        // Also check UserDefaults: ARESAppState.init() writes these before SAMRuntime
        // is constructed, so UserDefaults is a reliable pre-populated source.
        let udURL = UserDefaults.standard.string(forKey: "ARES.hermesGatewayURL")
        let udModel = UserDefaults.standard.string(forKey: "ARES.selectedModel")
        let udKey = UserDefaults.standard.string(forKey: "ARES.hermesAPIKey")

        self.resolvedBaseURL = appState.map { "\($0.hermesGatewayURL)/v1" }
            ?? udURL.map { "\($0)/v1" }
            ?? envURL
            ?? "http://localhost:8642/v1"

        self.resolvedModel = appState?.selectedModel
            ?? udModel
            ?? envModel
            ?? "hermes-agent"

        self.resolvedAPIKey = envKey ?? udKey ?? ""

        let cm = ConversationManager()
        self.conversationManager = cm

        let em = EndpointManager(conversationManager: cm)
        self.endpointManager = em

        let scs = SharedConversationService(conversationManager: cm)
        self.sharedConversationService = scs

        cm.injectAIProvider(em)
        cm.injectSystemPromptManager(SystemPromptManager.shared)
        scs.injectEndpointManager(em)

        // Wire ALICE image generation service into MCP tool layer
        let aliceService = ALICEImageGenerationService()
        cm.mcpManager.setImageGenerationService(aliceService)

        // Configure Hermes as the custom provider
        configureHermesProvider()
    }

    private func configureHermesProvider() {
        let config = ProviderConfiguration(
            providerId: "hermes-agent",
            providerType: .custom,
            isEnabled: true,
            apiKey: resolvedAPIKey,
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

        // SAM's EndpointManager only loads custom providers whose ID appears in
        // UserDefaults["saved_provider_ids"]. Without this, the provider_config_
        // entry above is written but never instantiated, and ChatWidget has no
        // provider to route to — messages go nowhere.
        var savedIds = UserDefaults.standard.stringArray(forKey: "saved_provider_ids") ?? []
        if !savedIds.contains("hermes-agent") {
            savedIds.append("hermes-agent")
            UserDefaults.standard.set(savedIds, forKey: "saved_provider_ids")
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

    /// Idempotent: lazily creates the Companion tab's conversation the first time
    /// the tab appears, and reuses it on every subsequent appearance so message
    /// history survives tab switches.
    func ensureCompanionConversation() {
        if companionMessageBus == nil {
            companionMessageBus = createConversation()
        }
    }
}
