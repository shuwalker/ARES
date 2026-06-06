import Foundation

// MARK: - Companion chat configuration
//
// Tracks the user's chosen model + provider for the Companion tab
// chat. Persisted to UserDefaults so the choice survives restarts.
// The model and provider are passed to `hermes` CLI as `-m` and
// `--provider` flags at send time.
//
// The list of available models is hard-coded here, mirroring the
// `providers:` block in `~/.hermes/config.yaml`. We don't auto-parse
// the config (it's not a stable API surface) — when you add a new
// provider, add a row here.

struct CompanionConfig: Codable, Equatable {

    /// Hermes model identifier, e.g. "gpt-5.5", "claude-sonnet-4", "minimax-m3:cloud".
    var model: String

    /// Hermes provider name, e.g. "openai-codex", "anthropic", "ollama-launch".
    var provider: String

    /// All available (provider, model) choices the picker can offer.
    /// Mirrors ~/.hermes/config.yaml providers.
    static let allChoices: [Choice] = [
        // Local
        Choice(provider: "ollama-local",  model: "gemma4:e4b-mlx",  displayName: "Gemma 4 (local)",      summary: "Runs on your Mac. Fast. Small. Good enough for short answers.",       group: .local,  speed: .fast, quality: .basic),
        Choice(provider: "ollama-local",  model: "qwen3:8b",       displayName: "Qwen 3 8B (local)",    summary: "Bigger local model. Slower, smarter than Gemma.",                  group: .local,  speed: .medium, quality: .good),
        Choice(provider: "ollama-launch", model: "qwen3-vl:8b",    displayName: "Qwen 3 VL 8B (local)", summary: "Local vision model. Sees images.",                                  group: .local,  speed: .medium, quality: .good),

        // Cloud via Ollama
        Choice(provider: "ollama-cloud",  model: "glm-5.1:cloud",  displayName: "GLM 5.1 (cloud)",      summary: "Cloud model via Ollama. Medium quality, medium speed.",            group: .cloud,  speed: .medium, quality: .good),
        Choice(provider: "ollama-launch", model: "minimax-m3:cloud", displayName: "MiniMax M3 (cloud)",summary: "Default. Cloud model. Fast, lightweight responses.",                group: .cloud,  speed: .fast, quality: .basic),

        // Frontier
        Choice(provider: "openai-codex",  model: "gpt-5.5",        displayName: "GPT-5.5 (Codex)",      summary: "OpenAI's latest. Excellent at code and reasoning. Slower.",       group: .frontier, speed: .slow, quality: .excellent),
        Choice(provider: "anthropic",     model: "claude-sonnet-4",displayName: "Claude Sonnet 4",      summary: "Anthropic's mid-tier. Strong writing, good at nuance.",          group: .frontier, speed: .slow, quality: .excellent),
        Choice(provider: "openai",        model: "gpt-4o",         displayName: "GPT-4o (OpenAI)",      summary: "OpenAI's workhorse. Fast, well-rounded.",                         group: .frontier, speed: .medium, quality: .veryGood),
        Choice(provider: "openrouter",    model: "anthropic/claude-sonnet-4", displayName: "Claude Sonnet 4 (OpenRouter)", summary: "Same as Anthropic, routed through OpenRouter.",    group: .frontier, speed: .slow, quality: .excellent),

        // Local Claude Code (uses the Claude Code CLI as a model)
        Choice(provider: "claude-code-local", model: "claude-code", displayName: "Claude Code (local)", summary: "Routes through the Claude Code CLI on localhost:8555.",          group: .local, speed: .medium, quality: .excellent),
    ]

    /// UserDefaults key for persistence.
    private static let defaultsKey = "com.ares.companion.config"

    /// Load the saved config, or fall back to the Hermes default
    /// (minimax-m3:cloud via ollama-launch).
    static func load() -> CompanionConfig {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let saved = try? JSONDecoder().decode(CompanionConfig.self, from: data) {
            return saved
        }
        return CompanionConfig(model: "minimax-m3:cloud", provider: "ollama-launch")
    }

    /// Save the config to UserDefaults.
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    /// Find a matching choice in the catalog. Used for displaying
    /// the current model name in the picker header.
    var currentChoice: Choice {
        Self.allChoices.first { $0.provider == provider && $0.model == model }
            ?? Choice(provider: provider, model: model, displayName: model, summary: "", group: .cloud, speed: .medium, quality: .basic)
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
                case .medium: return "tortoise"
                case .slow:   return "moon.zzz"
                }
            }
        }

        enum Quality: String {
            case basic, good, veryGood, excellent
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
