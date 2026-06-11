import Foundation
import ARESCore

// MARK: - Ollama Gateway Provider
//
// Connects to Ollama API (localhost:11434 by default) for local LLM inference.
// Supports streaming chat completions via the OpenAI-compatible endpoint.
// Discovers models at /api/tags and detects vision capability (if model name contains "vl").

public final class OllamaGatewayProvider: GatewayProvider, @unchecked Sendable {

    // MARK: - Configuration

    let baseURL: URL
    private let timeoutInterval: TimeInterval = 300

    public init(baseURL: URL = ARESConfiguration.shared.ollamaBaseURL) {
        self.baseURL = baseURL
    }

    // MARK: - GatewayProvider Protocol

    public var identifier: String { "ollama" }
    public var serviceName: String { "Ollama (Local)" }

    public var capabilities: Set<String> {
        let caps: Set<String> = ["reasoning", "streaming", "tools"]
        return caps
    }

    public func healthCheck() async throws -> GatewayHealth {
        let startTime = Date()
        do {
            let url = baseURL.appendingPathComponent("api/tags")
            var request = URLRequest(url: url, timeoutInterval: 5)
            let (_, response) = try await URLSession.shared.data(for: request)
            let elapsed = Date().timeIntervalSince(startTime) * 1000
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                return GatewayHealth(isHealthy: false, latencyMs: elapsed)
            }
            return GatewayHealth(isHealthy: true, latencyMs: elapsed)
        } catch {
            return GatewayHealth(isHealthy: false, latencyMs: Date().timeIntervalSince(startTime) * 1000)
        }
    }

    public func prompt(
        _ message: String,
        context: ConversationContext,
        options: GatewayOptions
    ) async throws -> GatewayResponse {
        // Collect stream into single response
        var accumulated = ""
        var tokenCount = TokenCount(input: 0, output: 0)

        for try await token in promptStream(message, context: context, options: options) {
            accumulated += token.text
            tokenCount = TokenCount(input: tokenCount.input, output: tokenCount.output + 1)
        }

        return GatewayResponse(
            text: accumulated,
            stopReason: .endTurn,
            tokenCount: tokenCount
        )
    }

    public func promptStream(
        _ message: String,
        context: ConversationContext,
        options: GatewayOptions
    ) -> AsyncStream<StreamedToken> {
        AsyncStream { (continuation: AsyncStream<StreamedToken>.Continuation) in
            Task {
                do {
                    let url = baseURL.appendingPathComponent("api/chat")

                    let messages = context.messages.map { msg -> [String: String] in
                        [
                            "role": msg.role.rawValue,
                            "content": msg.content
                        ]
                    }

                    var body: [String: Any] = [
                        "model": context.model ?? "gemma4:e4b",
                        "messages": messages,
                        "stream": true,
                        "temperature": options.temperature
                    ]
                    if let tools = options.tools, !tools.isEmpty {
                        body["tools"] = GatewayToolEncoding.openAIFunction(tools)
                    }

                    let requestBody = try JSONSerialization.data(withJSONObject: body)

                    var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = requestBody

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        throw OllamaError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
                    }

                    var tokenIndex = 0
                    var pendingToolCalls: [ToolCall] = []
                    for try await line in bytes.lines {
                        guard let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let message = json["message"] as? [String: Any] else {
                            continue
                        }

                        // Tool calls: {"message": {"tool_calls": [{"function": {"name": ..., "arguments": {...}}}]}}
                        if let rawCalls = message["tool_calls"] as? [[String: Any]] {
                            for rawCall in rawCalls {
                                guard let function = rawCall["function"] as? [String: Any],
                                      let name = function["name"] as? String else { continue }
                                let arguments = function["arguments"] as? [String: Any] ?? [:]
                                pendingToolCalls.append(ToolCall(
                                    toolName: name,
                                    input: ToolJSON.input(from: arguments)
                                ))
                            }
                        }

                        let content = message["content"] as? String ?? ""
                        let isFinished = json["done"] as? Bool ?? false
                        continuation.yield(StreamedToken(
                            text: content,
                            tokenIndex: tokenIndex,
                            isFinal: isFinished,
                            toolCalls: isFinished && !pendingToolCalls.isEmpty ? pendingToolCalls : nil
                        ))
                        tokenIndex += 1

                        if isFinished {
                            continuation.finish()
                            return
                        }
                    }

                    continuation.finish()

                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish()
                }
            }
        }
    }

    public func executeToolCall(
        _ call: ToolCall,
        context: ConversationContext
    ) async throws -> ToolResult {
        // Tool calls requested by the model are executed locally through the
        // ToolRouter (Ollama itself has no server-side tool execution).
        await ToolRouter.shared.execute(call)
    }

    public func getConfig() async throws -> GatewayConfig {
        let models = try await listModels()
        let hasVision = models.contains { $0.contains("vl") }
        return GatewayConfig(
            maxTokensPerRequest: 2048,
            maxRequestsPerMinute: 100,
            supportedModels: models,
            supportsStreaming: true,
            supportsToolCalling: false,
            supportsVision: hasVision
        )
    }

    public func listAvailableModels() async throws -> [GatewayModelChoice] {
        let models = try await listModels()
        return models.map {
            GatewayModelChoice(
                provider: identifier,
                model: $0,
                displayName: "\($0) (local)",
                summary: "Local Ollama model"
            )
        }
    }

    // MARK: - Session Management (stubs — Ollama has no session concept)

    public func sessionList(limit: Int) async throws -> [SessionSummary] {
        // Ollama does not support session management
        return []
    }

    public func branchSession(fromMessageId messageId: String) async throws -> SessionSummary {
        // Ollama does not support session branching
        throw OllamaError.unsupportedOperation("Ollama does not support session branching")
    }

    // MARK: - Ollama Specific APIs

    /// List all available models from Ollama.
    func listModels() async throws -> [String] {
        let url = baseURL.appendingPathComponent("api/tags")
        let (data, response) = try await URLSession.shared.data(from: url)

        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw OllamaError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }

        struct TagsResponse: Codable {
            let models: [Model]?
            struct Model: Codable {
                let name: String
            }
        }

        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        return decoded.models?.map { $0.name } ?? []
    }

    /// Pull (download) a model from Ollama registry.
    func pullModel(_ name: String) async throws {
        let url = baseURL.appendingPathComponent("api/pull")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = try JSONSerialization.data(withJSONObject: ["name": name])
        request.httpBody = body

        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw OllamaError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
    }

    /// Generate embeddings for a given prompt using Ollama.
    public func generateEmbeddings(prompt: String, model: String = "nomic-embed-text") async throws -> [Double] {
        let url = baseURL.appendingPathComponent("api/embeddings")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "model": model,
            "prompt": prompt
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OllamaError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        struct EmbeddingsResponse: Codable {
            let embedding: [Double]
        }
        
        let decoded = try JSONDecoder().decode(EmbeddingsResponse.self, from: data)
        return decoded.embedding
    }
}

// MARK: - Error

enum OllamaError: LocalizedError, Sendable {
    case httpError(statusCode: Int)
    case decodingError(String)
    case cancelled
    case unsupportedOperation(String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code):
            return "Ollama HTTP \(code)"
        case .decodingError(let msg):
            return "Decoding error: \(msg)"
        case .cancelled:
            return "Request cancelled"
        case .unsupportedOperation(let msg):
            return "Unsupported operation: \(msg)"
        }
    }
}
