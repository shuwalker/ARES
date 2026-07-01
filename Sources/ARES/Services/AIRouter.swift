import Foundation

// MARK: - AI Router
// Routes every request to the best available AI engine.
// ARES doesn't have multiple chats — it has ONE AI that uses every engine.
//
// Refactored: 5 separate engine classes collapsed into:
//   1. OpenAIChatEngine — single class for all OpenAI-compatible APIs
//      (Hermes, Ollama, Claude via proxy, Gemini via proxy, any /v1/chat/completions endpoint)
//   2. ClaudeCliEngine — subprocess pipe, not HTTP (kept as-is)
//
// This eliminates ~200 lines of duplicated HTTP boilerplate.
// To add a new provider: register(.openAI(id:model:baseURL:apiKey:))
// No new class needed.

final class AIRouter: @unchecked Sendable {
    static let shared = AIRouter()

    private var engines: [AIEngine] = []
    private var priorityOrder: [String] = []

    func register(_ engine: AIEngine, priority: Int? = nil) {
        engines.append(engine)
        if let p = priority {
            priorityOrder.append(engine.id)
            // Sort by priority: lower number = higher priority
            engines.sort { a, b in
                let pa = priorityOrder.firstIndex(of: a.id) ?? Int.max
                let pb = priorityOrder.firstIndex(of: b.id) ?? Int.max
                return pa < pb
            }
        }
    }

    func chat(messages: [[String: String]], preferredEngine: String? = nil) async throws -> String {
        // If a specific engine is preferred, try it first
        if let preferred = preferredEngine, let engine = engines.first(where: { $0.id == preferred }) {
            return try await engine.chat(messages: messages)
        }

        // Try engines in priority order
        var lastError: Error?
        for engine in engines {
            guard await engine.checkAvailability() else { continue }
            do {
                return try await engine.chat(messages: messages)
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError ?? RouterError.noEnginesAvailable
    }

    var availableEngines: [String] {
        engines.map { $0.id }
    }

    var statusDescription: String {
        engines.map { "\($0.id): \($0.displayName)" }.joined(separator: "\n")
    }
}

enum RouterError: LocalizedError {
    case noEnginesAvailable
    var errorDescription: String? { "No AI engines available. Check your connections." }
}

// MARK: - AI Engine Protocol

protocol AIEngine: AnyObject {
    var id: String { get }
    var displayName: String { get }
    func checkAvailability() async -> Bool
    func chat(messages: [[String: String]]) async throws -> String
}

// MARK: - OpenAI-Compatible Chat Engine
// Single class handles any API that speaks OpenAI's /v1/chat/completions format.
// This covers: Hermes Gateway, Ollama (/v1/), OpenAI, Groq, OpenRouter,
// LiteLLM proxy, vLLM, LM Studio, and any OpenAI-compatible endpoint.
//
// For providers with non-OpenAI native APIs (Anthropic, Gemini),
// point baseURL at an OpenAI-compatible proxy (LiteLLM, OpenRouter, etc.)

final class OpenAIChatEngine: AIEngine, @unchecked Sendable {
    let id: String
    let displayName: String
    private let baseURL: String
    private let apiKey: String
    private let model: String
    private let healthEndpoint: String?

    init(id: String, displayName: String, baseURL: String, apiKey: String = "", model: String = "", healthEndpoint: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.healthEndpoint = healthEndpoint
    }

    func checkAvailability() async -> Bool {
        // If a health endpoint is specified, check it
        if let health = healthEndpoint, let url = URL(string: health) {
            return (try? await URLSession.shared.data(from: url))
                .map { ($0.1 as? HTTPURLResponse)?.statusCode == 200 } ?? false
        }
        // Otherwise, if we have a base URL, try a quick HEAD on the completions endpoint
        if let url = URL(string: "\(baseURL)/v1/models") {
            var req = URLRequest(url: url, timeoutInterval: 5)
            if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
            return (try? await URLSession.shared.data(for: req))
                .map { ($0.1 as? HTTPURLResponse)?.statusCode == 200 } ?? false
        }
        return false
    }

    func chat(messages: [[String: String]]) async throws -> String {
        let url = URL(string: "\(baseURL)/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        req.timeoutInterval = 300

        // Normalize roles: "ares" → "assistant"
        let normalizedMessages = messages.map { msg -> [String: String] in
            let role = msg["role"] == "ares" ? "assistant" : msg["role"] ?? "user"
            return ["role": role, "content": msg["content"] ?? ""]
        }

        var body: [String: Any] = [
            "messages": normalizedMessages,
            "stream": false
        ]
        if !model.isEmpty { body["model"] = model }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let bodyStr = String(data: data, encoding: .utf8) ?? "no response body"
            throw EngineError.httpError(id: id, statusCode: statusCode, body: bodyStr)
        }

        struct ChatCompletionResponse: Codable {
            let choices: [Choice]?
            struct Choice: Codable {
                let message: Message?
                struct Message: Codable {
                    let content: String?
                }
            }
        }

        let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        return decoded.choices?.first?.message?.content ?? ""
    }
}

enum EngineError: LocalizedError {
    case httpError(id: String, statusCode: Int, body: String)
    var errorDescription: String? {
        switch self {
        case .httpError(let id, let code, let body):
            return "Engine '\(id)' returned HTTP \(code): \(body)"
        }
    }
}

// MARK: - Claude CLI Engine (subprocess pipe, not HTTP)
// Kept separate because it's a local binary invocation, not an HTTP API.

final class ClaudeCliEngine: AIEngine, @unchecked Sendable {
    let id = "claude-cli"
    let displayName = "Claude Code CLI"
    private let cliPath: String

    init(cliPath: String = "\(NSHomeDirectory())/.local/bin/claude") {
        self.cliPath = cliPath
    }

    var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: cliPath) }

    func checkAvailability() async -> Bool { isAvailable }

    func chat(messages: [[String: String]]) async throws -> String {
        // Build prompt from messages
        let prompt = messages.map { msg -> String in
            let role = msg["role"] == "ares" ? "Assistant" : "User"
            return "\(role): \(msg["content"] ?? "")"
        }.joined(separator: "\n\n") + "\n\nAssistant:"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: cliPath)
        process.arguments = ["--print", prompt]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorStr = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ClaudeCliError.executionFailed(errorStr)
        }

        return output
    }
}

enum ClaudeCliError: LocalizedError {
    case executionFailed(String)
    var errorDescription: String? {
        switch self {
        case .executionFailed(let msg): return "Claude CLI: \(msg)"
        }
    }
}

// MARK: - Convenience Factory
// Usage in ARESApp.swift:
//   router.register(.hermes(url: "http://localhost:8642"), priority: 1)
//   router.register(.ollama(model: "gemma4:e4b"), priority: 5)
//   router.register(.openAI(id: "openai", model: "gpt-4o", apiKey: "..."), priority: 3)

extension AIRouter {
    enum EngineFactory {
        /// Hermes Agent Gateway — OpenAI-compatible at /v1/chat/completions
        static func hermes(url: String = "http://localhost:8642") -> OpenAIChatEngine {
            OpenAIChatEngine(
                id: "hermes",
                displayName: "Hermes Agent",
                baseURL: url,
                model: "",
                healthEndpoint: "\(url)/health"
            )
        }

        /// Ollama local model — OpenAI-compatible at /v1/chat/completions
        static func ollama(model: String = "gemma4:e4b", port: Int = 11434) -> OpenAIChatEngine {
            OpenAIChatEngine(
                id: "local",
                displayName: "Local (Ollama)",
                baseURL: "http://localhost:\(port)",
                model: model,
                healthEndpoint: "http://localhost:\(port)/api/tags"
            )
        }

        /// Generic OpenAI-compatible API (OpenAI, Groq, OpenRouter, LiteLLM, vLLM, etc.)
        static func openAI(id: String, displayName: String, baseURL: String, apiKey: String, model: String) -> OpenAIChatEngine {
            OpenAIChatEngine(
                id: id,
                displayName: displayName,
                baseURL: baseURL,
                apiKey: apiKey,
                model: model
            )
        }

        /// Claude CLI — subprocess pipe (not HTTP)
        static func claudeCLI() -> ClaudeCliEngine {
            ClaudeCliEngine()
        }
    }
}