import Foundation

// MARK: - AI Router
// Routes every request to the best available AI engine.
// ARES doesn't have multiple chats — it has ONE AI that uses every engine.

final class AIRouter: @unchecked Sendable {
    static let shared = AIRouter()

    private var engines: [AIEngine] = []

    func register(_ engine: AIEngine) {
        engines.append(engine)
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

// MARK: - Hermes Engine

final class HermesEngine: AIEngine, @unchecked Sendable {
    let id = "hermes"
    let displayName = "Hermes Agent"
    private let gateway: HermesGateway

    init(url: String) {
        self.gateway = HermesGateway(url: url)
    }

    var isAvailable: Bool { true }

    func checkAvailability() async -> Bool {
        (try? await gateway.health()) ?? false
    }

    func chat(messages: [[String: String]]) async throws -> String {
        try await gateway.chat(messages: messages)
    }
}

// MARK: - Claude CLI Engine (direct pipe, no API key needed)

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

// MARK: - Gemini Engine (web UI wrapper - no API key needed)

final class GeminiEngine: AIEngine, @unchecked Sendable {
    let id = "gemini"
    let displayName = "Google Gemini"
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    var isAvailable: Bool { !apiKey.isEmpty }

    func checkAvailability() async -> Bool { isAvailable }

    func chat(messages: [[String: String]]) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 60

        // Convert messages to Gemini format
        let contents = messages.map { msg -> [String: Any] in
            let role = msg["role"] == "ares" ? "model" : "user"
            return [
                "role": role,
                "parts": [["text": msg["content"] ?? ""]]
            ]
        }

        let body: [String: Any] = ["contents": contents]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GeminiError.apiError
        }

        struct GeminiResponse: Codable {
            let candidates: [Candidate]?
            struct Candidate: Codable {
                let content: Content?
                struct Content: Codable {
                    let parts: [Part]?
                    struct Part: Codable {
                        let text: String?
                    }
                }
            }
        }

        let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
        return decoded.candidates?.first?.content?.parts?.first?.text ?? ""
    }
}

enum GeminiError: LocalizedError {
    case apiError
    case notFound
    var errorDescription: String? {
        switch self {
        case .apiError: return "Gemini API error"
        case .notFound: return "Gemini not found on this system"
        }
    }
}

// MARK: - Claude Engine

final class ClaudeEngine: AIEngine, @unchecked Sendable {
    let id = "claude"
    let displayName = "Claude (Anthropic)"
    private let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    var isAvailable: Bool { !apiKey.isEmpty }

    func checkAvailability() async -> Bool { isAvailable }

    func chat(messages: [[String: String]]) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.timeoutInterval = 60

        let systemMsg = messages.first { $0["role"] == "system" }
        let chatMessages = messages.filter { $0["role"] != "system" }.map { msg -> [String: String] in
            ["role": msg["role"] == "ares" ? "assistant" : msg["role"] ?? "user", "content": msg["content"] ?? ""]
        }

        var body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 4096,
            "messages": chatMessages
        ]
        if let system = systemMsg {
            body["system"] = system["content"]
        }

        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ClaudeError.apiError
        }

        struct ClaudeResponse: Codable {
            let content: [Content]?
            struct Content: Codable {
                let text: String?
            }
        }

        let decoded = try JSONDecoder().decode(ClaudeResponse.self, from: data)
        return decoded.content?.first?.text ?? ""
    }
}

enum ClaudeError: LocalizedError {
    case apiError
    case notFound
    var errorDescription: String? {
        switch self {
        case .apiError: return "Claude API error"
        case .notFound: return "Claude not found on this system"
        }
    }
}

// MARK: - Local Engine (Ollama)

final class LocalEngine: AIEngine, @unchecked Sendable {
    let id = "local"
    let displayName = "Local (Ollama)"
    private let model: String

    init(model: String = "gemma4:e4b") {
        self.model = model
    }

    var isAvailable: Bool { true }

    func checkAvailability() async -> Bool {
        guard let url = URL(string: "http://localhost:11434/api/tags") else { return false }
        return (try? await URLSession.shared.data(from: url)).map { ($0.1 as? HTTPURLResponse)?.statusCode == 200 } ?? false
    }

    func chat(messages: [[String: String]]) async throws -> String {
        let url = URL(string: "http://localhost:11434/api/chat")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 300

        let ollamaMessages = messages.map { msg -> [String: String] in
            ["role": msg["role"] == "ares" ? "assistant" : msg["role"] ?? "user", "content": msg["content"] ?? ""]
        }

        let body: [String: Any] = [
            "model": model,
            "messages": ollamaMessages,
            "stream": false
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw LocalError.apiError
        }

        struct OllamaResponse: Codable {
            let message: Message?
            struct Message: Codable {
                let content: String
            }
        }

        let decoded = try JSONDecoder().decode(OllamaResponse.self, from: data)
        return decoded.message?.content ?? ""
    }
}

enum LocalError: LocalizedError {
    case apiError
    var errorDescription: String? { "Local model error" }
}
