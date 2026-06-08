import Foundation
import ARESCore

// MARK: - Ollama Gateway Provider
//
// Connects to Ollama API (localhost:11434 by default) for local LLM inference.
// Supports streaming chat completions via the OpenAI-compatible endpoint.
// Discovers models at /api/tags and detects vision capability (if model name contains "vl").

final class OllamaGatewayProvider: GatewayProvider, @unchecked Sendable {

    // MARK: - Configuration

    let baseURL: URL
    private let timeoutInterval: TimeInterval = 300

    init(baseURL: URL = URL(string: "http://localhost:11434")!) {
        self.baseURL = baseURL
    }

    // MARK: - GatewayProvider Protocol

    var identifier: String { "ollama" }
    var serviceName: String { "Ollama (Local)" }

    var capabilities: Set<String> {
        var caps: Set<String> = ["reasoning", "streaming"]
        return caps
    }

    func healthCheck() async throws -> GatewayHealth {
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

    func prompt(
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

    func promptStream(
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
                    for try await line in bytes.lines {
                        guard let data = line.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let message = json["message"] as? [String: String],
                              let content = message["content"] else {
                            continue
                        }

                        let isFinished = json["done"] as? Bool ?? false
                        continuation.yield(StreamedToken(
                            text: content,
                            tokenIndex: tokenIndex,
                            isFinal: isFinished
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

    func executeToolCall(
        _ call: ToolCall,
        context: ConversationContext
    ) async throws -> ToolResult {
        // Ollama doesn't support tool calling natively; return not implemented
        return ToolResult(success: false, data: AnyCodable.string("Tool calling not supported in Ollama"))
    }

    func getConfig() async throws -> GatewayConfig {
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

    // MARK: - Session Management (stubs — Ollama has no session concept)

    func sessionList(limit: Int) async throws -> [SessionSummary] {
        // Ollama does not support session management
        return []
    }

    func branchSession(fromMessageId messageId: String) async throws -> SessionSummary {
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
