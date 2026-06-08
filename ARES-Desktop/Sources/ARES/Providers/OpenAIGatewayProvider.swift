import Foundation
import ARESCore
import os

private let openAIGatewayLog = Logger(subsystem: "com.ares", category: "OpenAIGateway")

final class OpenAIGatewayProvider: GatewayProvider, @unchecked Sendable {
    let baseURL = URL(string: "https://api.openai.com/v1/chat/completions")!
    let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    var identifier: String { "openai" }
    var serviceName: String { "OpenAI" }
    var capabilities: Set<String> { ["reasoning", "streaming"] }

    func healthCheck() async throws -> GatewayHealth {
        guard !apiKey.isEmpty else {
            return GatewayHealth(isHealthy: false, latencyMs: 0)
        }
        return GatewayHealth(isHealthy: true, latencyMs: 50)
    }

    func prompt(_ message: String, context: ConversationContext, options: GatewayOptions) async throws -> GatewayResponse {
        var accumulated = ""
        var tokenCount = TokenCount(input: 0, output: 0)

        for try await token in promptStream(message, context: context, options: options) {
            accumulated += token.text
            tokenCount = TokenCount(input: tokenCount.input, output: tokenCount.output + 1)
        }

        return GatewayResponse(text: accumulated, stopReason: .endTurn, tokenCount: tokenCount)
    }

    func promptStream(_ message: String, context: ConversationContext, options: GatewayOptions) -> AsyncStream<StreamedToken> {
        AsyncStream { continuation in
            Task {
                do {
                    let messages = context.messages.map { msg -> [String: String] in
                        ["role": msg.role.rawValue, "content": msg.content]
                    }

                    let body: [String: Any] = [
                        "model": context.model ?? "gpt-4o",
                        "messages": messages,
                        "stream": true,
                        "temperature": options.temperature
                    ]

                    var request = URLRequest(url: baseURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        continuation.yield(StreamedToken(text: "Error: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)", isFinal: true))
                        continuation.finish()
                        return
                    }

                    var tokenIndex = 0
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = line.dropFirst(6)
                        guard jsonStr != "[DONE]" else { break }

                        if let data = jsonStr.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let choices = json["choices"] as? [[String: Any]],
                           let first = choices.first,
                           let delta = first["delta"] as? [String: Any],
                           let content = delta["content"] as? String {
                           
                            continuation.yield(StreamedToken(text: content, tokenIndex: tokenIndex, isFinal: false))
                            tokenIndex += 1
                        }
                    }
                    continuation.yield(StreamedToken(text: "", tokenIndex: tokenIndex, isFinal: true))
                    continuation.finish()
                } catch {
                    openAIGatewayLog.error("Streaming failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish()
                }
            }
        }
    }

    func executeToolCall(_ call: ToolCall, context: ConversationContext) async throws -> ToolResult {
        return ToolResult(success: false, data: AnyCodable.string("Tool calling not yet implemented"))
    }

    func getConfig() async throws -> GatewayConfig {
        return GatewayConfig(supportedModels: ["gpt-4o", "gpt-4-turbo", "gpt-3.5-turbo"])
    }

    func sessionList(limit: Int) async throws -> [SessionSummary] { return [] }
    func branchSession(fromMessageId messageId: String) async throws -> SessionSummary { throw NSError(domain: "OpenAI", code: 1, userInfo: nil) }
}
