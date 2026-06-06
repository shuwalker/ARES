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

    // MARK: - Model catalog

    /// All available (provider, model) choices the picker can offer.
    /// Mirrors ~/.hermes/config.yaml providers + the special "hermes-agent" entry.
    static let allChoices: [Choice] = [
        // Full agent (default — uses Hermes Gateway with full tool access)
        Choice(provider: "hermes-gateway", model: "hermes-agent", displayName: "Hermes Agent (full)", summary: "Full agent with tools, memory, skills — same as TUI.", group: .local, speed: .medium, quality: .excellent),

        // Local
        Choice(provider: "ollama-local", model: "gemma4:e4b-mlx", displayName: "Gemma 4 (local)", summary: "Runs on your Mac. Fast. Small. Good enough for short answers.", group: .local, speed: .fast, quality: .basic),
        Choice(provider: "ollama-local", model: "qwen3:8b", displayName: "Qwen 3 8B (local)", summary: "Bigger local model. Slower, smarter than Gemma.", group: .local, speed: .medium, quality: .good),

        // Cloud via Ollama
        Choice(provider: "ollama-cloud", model: "glm-5.1:cloud", displayName: "GLM 5.1 (cloud)", summary: "Cloud model via Ollama. Medium quality, medium speed.", group: .cloud, speed: .medium, quality: .good),
        Choice(provider: "ollama-launch", model: "minimax-m3:cloud", displayName: "MiniMax M3 (cloud)", summary: "Cloud model. Fast, lightweight responses.", group: .cloud, speed: .fast, quality: .basic),

        // Frontier
        Choice(provider: "openai-codex", model: "gpt-5.5", displayName: "GPT-5.5 (Codex)", summary: "OpenAI's latest. Excellent at code and reasoning. Slower.", group: .frontier, speed: .slow, quality: .excellent),
        Choice(provider: "anthropic", model: "claude-sonnet-4", displayName: "Claude Sonnet 4", summary: "Anthropic's mid-tier. Strong writing, good at nuance.", group: .frontier, speed: .slow, quality: .excellent),
    ]

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
    var currentChoice: Choice {
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
        gatewayURL: String = "http://localhost:8642",
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