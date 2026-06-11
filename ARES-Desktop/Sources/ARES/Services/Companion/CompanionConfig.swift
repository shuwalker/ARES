import Foundation
import ARESCore

// MARK: - Companion Configuration
//
// Manages the Companion tab's connection to the Hermes Gateway.
// The Gateway URL defaults to http://localhost:8642 and the API key
// is read from ~/.hermes/.env (API_SERVER_KEY).
//
// The model picker lets users choose which backend the agent uses.
// "hermes-agent" activates the full agent (tools, memory, skills) —
// this is the default and what makes the Companion a true Hermes
// replacement, not just a raw LLM chat.

struct CompanionConfig: Codable, Equatable {

    // MARK: - Connection settings

    /// The Hermes Gateway base URL. Default: http://localhost:8642
    var gatewayURL: String

    /// The API key for authenticating with the Gateway.
    /// Read from ~/.hermes/.env at runtime; empty string means "try anyway".
    var apiKey: String

    /// The model identifier sent in chat requests.
    /// "hermes-agent" activates the full agent (tools, memory, skills).
    /// Use a raw model name for stateless completions.
    var model: String

    /// The provider label (kept for CLI fallback compatibility and picker display).
    var provider: String

    /// Maximum conversation history turns to include as context.
    var maxHistoryTurns: Int

    /// A cached list of available models, populated at runtime.
    @MainActor static var allChoices: [Choice] = [
        Choice(provider: "hermes", model: "hermes-agent", displayName: "Hermes Agent (full)", summary: "Full agent with tools, memory, skills", group: .local, speed: .medium, quality: .excellent)
    ]

    /// Fetches all models from all provided gateways dynamically.
    static func refreshChoices(gateways: [any GatewayProvider]) async {
        var newChoices: [Choice] = []
        for gateway in gateways {
            if let models = try? await gateway.listAvailableModels() {
                for model in models {
                    let group: Choice.Group = gateway.identifier == "ollama" ? .local : .cloud
                    newChoices.append(Choice(
                        provider: model.provider,
                        model: model.model,
                        displayName: model.displayName,
                        summary: model.summary,
                        group: group,
                        speed: .medium,
                        quality: .good
                    ))
                }
            }
        }
        
        // Always ensure hermes-agent is at the top
        let hermes = newChoices.first(where: { $0.model == "hermes-agent" }) ?? Choice(provider: "hermes", model: "hermes-agent", displayName: "Hermes Agent (full)", summary: "Full agent with tools, memory, skills", group: .local, speed: .medium, quality: .excellent)
        
        var filtered = newChoices.filter { $0.model != "hermes-agent" }
        filtered.insert(hermes, at: 0)
        
        await MainActor.run {
            self.allChoices = filtered
        }
    }

    /// UserDefaults key for persistence.
    private static let defaultsKey = "com.ares.companion.config"

    /// Load the saved config, or fall back to the full agent default.
    static func load() -> CompanionConfig {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(CompanionConfig.self, from: data) {
            return saved
        }
        return CompanionConfig()
    }

    /// Save the config to UserDefaults.
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    /// Find a matching choice in the catalog.
    @MainActor var currentChoice: Choice {
        Self.allChoices.first { $0.provider == provider && $0.model == model }
            ?? Choice(provider: provider, model: model, displayName: model, summary: "", group: .cloud, speed: .medium, quality: .basic)
    }

    /// Reads the API_SERVER_KEY from ~/.hermes/.env at runtime.
    static func readAPIKeyFromEnv() -> String {
        let envPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".hermes/.env")

        guard let contents = try? String(contentsOf: envPath, encoding: .utf8) else {
            return ""
        }

        for line in contents.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("API_SERVER_KEY=") {
                let value = trimmed
                    .replacingOccurrences(of: "API_SERVER_KEY=", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return value
            }
        }
        return ""
    }

    init(
        gatewayURL: String = ARESConfiguration.shared.hermesURL,
        apiKey: String = "",
        model: String = "hermes-agent",
        provider: String = "hermes-gateway",
        maxHistoryTurns: Int = 20
    ) {
        self.gatewayURL = gatewayURL
        self.apiKey = apiKey
        self.model = model
        self.provider = provider
        self.maxHistoryTurns = maxHistoryTurns
    }

    // MARK: - Choice model

    struct Choice: Identifiable, Hashable {
        let provider: String
        let model: String
        let displayName: String
        let summary: String
        let group: Group
        let speed: Speed
        let quality: Quality

        var id: String { "\(provider)/\(model)" }

        enum Group: String, CaseIterable, Identifiable {
            case local, cloud, frontier
            var id: String { rawValue }
            var displayName: String {
                switch self {
                case .local:    return "Local"
                case .cloud:    return "Cloud"
                case .frontier: return "Frontier"
                }
            }
        }

        enum Speed: String {
            case fast, medium, slow
            var icon: String {
                switch self {
                case .fast:   return "hare"
                case .medium:  return "tortoise"
                case .slow:    return "snail"
                }
            }
            var color: String {
                switch self {
                case .fast:   return "green"
                case .medium:  return "yellow"
                case .slow:    return "red"
                }
            }
        }

        enum Quality: String {
            case basic, good, veryGood, excellent
            var stars: Int {
                switch self {
                case .basic:     return 1
                case .good:      return 2
                case .veryGood:  return 3
                case .excellent: return 4
                }
            }
            var label: String {
                switch self {
                case .basic:     return "Basic"
                case .good:      return "Good"
                case .veryGood:  return "Very Good"
                case .excellent: return "Excellent"
                }
            }
        }
    }
}