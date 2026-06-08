import Foundation
import ARESCore
import os

private let claudeGatewayLog = Logger(subsystem: "com.ares", category: "ClaudeGateway")

final class ClaudeGatewayProvider: GatewayProvider, @unchecked Sendable {
    let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    let apiKey: String

    init(apiKey: String) {
        self.apiKey = apiKey
    }

    var identifier: String { "claude" }
    var serviceName: String { "Anthropic Claude" }
    var capabilities: Set<String> { ["reasoning", "streaming"] }

    func healthCheck() async throws -> GatewayHealth {
        guard !apiKey.isEmpty else {
            return GatewayHealth(isHealthy: false, latencyMs: 0)
        }
        // Actually ping the Anthropic API with a minimal request instead of fabricating latency
        let start = ContinuousClock.now
        let body: [String: Any] = [
            "model": "claude-3-5-sonnet-20240620",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]]
        ]
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 8
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let elapsed = ContinuousClock.now - start
            let ms = Int(Duration.components(seconds: elapsed.components.seconds, attoseconds: elapsed.components.attoseconds).milliseconds)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            // 200 = healthy, 401/403 = bad key (unhealthy), 429 = rate-limited but key is valid
            let isHealthy = statusCode == 200 || statusCode == 429
            return GatewayHealth(isHealthy: isHealthy, latencyMs: max(ms, 1))
        } catch {
            return GatewayHealth(isHealthy: false, latencyMs: 0)
        }
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
                    // Extract system prompt if any, Claude requires it separate
                    let systemMsg = context.messages.first { $0.role == .system }?.content
                    let chatMessages = context.messages.filter { $0.role != .system }.map { msg -> [String: String] in
                        ["role": msg.role.rawValue, "content": msg.content]
                    }

                    var body: [String: Any] = [
                        "model": context.model ?? "claude-3-5-sonnet-20240620",
                        "messages": chatMessages,
                        "stream": true,
                        "max_tokens": options.maxTokens
                    ]
                    if let sys = systemMsg {
                        body["system"] = sys
                    }

                    var request = URLRequest(url: baseURL)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
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

                        if let data = jsonStr.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let type = json["type"] as? String {
                           
                            if type == "content_block_delta",
                               let delta = json["delta"] as? [String: Any],
                               let text = delta["text"] as? String {
                                continuation.yield(StreamedToken(text: text, tokenIndex: tokenIndex, isFinal: false))
                                tokenIndex += 1
                            } else if type == "message_stop" {
                                break
                            }
                        }
                    }
                    continuation.yield(StreamedToken(text: "", tokenIndex: tokenIndex, isFinal: true))
                    continuation.finish()
                } catch {
                    claudeGatewayLog.error("Streaming failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish()
                }
            }
        }
    }

    func executeToolCall(_ call: ToolCall, context: ConversationContext) async throws -> ToolResult {
        // Anthropic tool_result flow: submit the tool result as a user message
        // with tool_result content block so the model continues the conversation.
        let startTime = ContinuousClock.now
        
        let toolResultBlock: [String: Any] = [
            "type": "tool_result",
            "tool_use_id": call.id,
            "content": String(describing: call.input)
        ]
        
        let priorMessages = context.messages.map { msg -> [String: Any] in
            ["role": msg.role.rawValue, "content": msg.content]
        }
        
        let toolResultMessage: [String: Any] = [
            "role": "user",
            "content": [toolResultBlock]
        ]
        
        let body: [String: Any] = [
            "model": context.model ?? "claude-3-5-sonnet-20240620",
            "max_tokens": 4096,
            "messages": priorMessages + [toolResultMessage]
        ]
        
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 30
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsed = ContinuousClock.now - startTime
            let ms = Double(Duration.components(seconds: elapsed.components.seconds, attoseconds: elapsed.components.attoseconds).milliseconds)
            let httpStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            
            guard httpStatus == 200 else {
                let bodyStr = String(data: data, encoding: .utf8) ?? "empty"
                return ToolResult(
                    success: false,
                    error: ToolError(code: "http_\(httpStatus)", message: bodyStr),
                    executionTimeMs: ms
                )
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let content = json["content"] as? [[String: Any]],
               let textBlock = content.first(where: { $0["type"] as? String == "text" }),
               let text = textBlock["text"] as? String {
                return ToolResult(
                    success: true,
                    data: AnyCodable.string(text),
                    executionTimeMs: ms
                )
            }
            
            return ToolResult(
                success: true,
                data: AnyCodable.string("Tool result submitted, no text response"),
                executionTimeMs: ms
            )
        } catch {
            return ToolResult(
                success: false,
                error: ToolError(code: "network", message: error.localizedDescription),
                executionTimeMs: 0
            )
        }
    }

    func getConfig() async throws -> GatewayConfig {
        return GatewayConfig(supportedModels: ["claude-3-5-sonnet-20240620", "claude-3-haiku-20240307"])
    }

    func sessionList(limit: Int) async throws -> [SessionSummary] { return [] }
    func branchSession(fromMessageId messageId: String) async throws -> SessionSummary { throw NSError(domain: "Claude", code: 1, userInfo: nil) }
}
