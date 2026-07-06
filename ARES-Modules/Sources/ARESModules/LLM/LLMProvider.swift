// MARK: - LLM Provider Protocol
// Extracted from CrewAI's BaseLLM + LLM factory pattern

import Foundation

public protocol LLMProvider: AnyObject {
    var id: String { get }
    var displayName: String { get }
    var contextWindow: Int { get }
    var supportsTools: Bool { get }
    func complete(messages: [[String: String]], tools: [[String: Any]]?) async throws -> LLMResponse
}

public struct LLMResponse: Sendable {
    public let content: String
    public let finishReason: String
    public let usage: TokenUsage?
}

public struct TokenUsage: Sendable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
}

// MARK: - LLM Router (CrewAI pattern)
// Routes to the best available provider with fallback

public final class LLMRouter: @unchecked Sendable {
    public static let shared = LLMRouter()
    private var providers: [LLMProvider] = []

    public func register(_ provider: LLMProvider) {
        providers.append(provider)
    }

    public func complete(messages: [[String: String]], preferredProvider: String? = nil) async throws -> LLMResponse {
        if let preferred = preferredProvider, let provider = providers.first(where: { $0.id == preferred }) {
            return try await provider.complete(messages: messages, tools: nil)
        }
        var lastError: Error?
        for provider in providers {
            do {
                return try await provider.complete(messages: messages, tools: nil)
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError ?? RouterError.noProviderAvailable
    }

    public var availableProviders: [String] { providers.map { $0.id } }
}

public enum RouterError: LocalizedError {
    case noProviderAvailable
    public var errorDescription: String? { "No LLM provider available" }
}

// MARK: - OpenAI-Compatible Provider (CrewAI pattern)
// Handles any OpenAI-compatible API (Ollama, vLLM, etc.)

public final class OpenAICompatibleProvider: LLMProvider, @unchecked Sendable {
    public let id: String
    public let displayName: String
    public let contextWindow: Int
    public let supportsTools: Bool
    private let baseURL: String
    private let apiKey: String
    private let model: String

    public init(id: String, displayName: String, baseURL: String, apiKey: String = "", model: String, contextWindow: Int = 4096, supportsTools: Bool = false) {
        self.id = id
        self.displayName = displayName
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.contextWindow = contextWindow
        self.supportsTools = supportsTools
    }

    public func complete(messages: [[String: String]], tools: [[String: Any]]?) async throws -> LLMResponse {
        let url = URL(string: "\(baseURL)/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        req.timeoutInterval = 300

        var body: [String: Any] = ["model": model, "messages": messages, "stream": false]
        if let tools = tools { body["tools"] = tools }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ProviderError.httpError
        }

        struct Response: Codable {
            let choices: [Choice]
            let usage: Usage?
            struct Choice: Codable { let message: Message; let finish_reason: String? }
            struct Message: Codable { let content: String? }
            struct Usage: Codable { let prompt_tokens: Int; let completion_tokens: Int; let total_tokens: Int }
        }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return LLMResponse(
            content: decoded.choices.first?.message.content ?? "",
            finishReason: decoded.choices.first?.finish_reason ?? "stop",
            usage: decoded.usage.map { TokenUsage(promptTokens: $0.prompt_tokens, completionTokens: $0.completion_tokens, totalTokens: $0.total_tokens) }
        )
    }
}

public enum ProviderError: LocalizedError {
    case httpError
    public var errorDescription: String? { "Provider HTTP error" }
}
