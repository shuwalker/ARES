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
    var capabilities: Set<String> { ["reasoning", "streaming", "tools"] }

    func healthCheck() async throws -> GatewayHealth {
        guard !apiKey.isEmpty else {
            return GatewayHealth(isHealthy: false, latencyMs: 0)
        }
        // Actually ping the Anthropic API with a minimal request instead of fabricating latency
        let start = CFAbsoluteTimeGetCurrent()
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
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let ms = elapsed * 1000.0
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            // 200 = healthy, 401/403 = bad key (unhealthy), 429 = rate-limited but key is valid
            let isHealthy = statusCode == 200 || statusCode == 429
            return GatewayHealth(isHealthy: isHealthy, latencyMs: max(ms, 1.0))
        } catch {
            return GatewayHealth(isHealthy: false, latencyMs: 0)
        }
    }

    func prompt(_ message: String, context: ConversationContext, options: GatewayOptions) async throws -> GatewayResponse {
        var accumulated = ""
        var toolCalls: [ToolCall] = []
        var tokenCount = TokenCount(input: 0, output: 0)

        for try await token in promptStream(message, context: context, options: options) {
            accumulated += token.text
            tokenCount = TokenCount(input: tokenCount.input, output: tokenCount.output + 1)
            if let calls = token.toolCalls {
                toolCalls.append(contentsOf: calls)
            }
        }

        return GatewayResponse(
            text: accumulated,
            toolCalls: toolCalls,
            stopReason: toolCalls.isEmpty ? .endTurn : .toolCall,
            tokenCount: tokenCount
        )
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
                    if let sys = systemMsg ?? options.systemPrompt {
                        body["system"] = sys
                    }
                    if let tools = options.tools, !tools.isEmpty {
                        body["tools"] = GatewayToolEncoding.anthropic(tools)
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
                    var completedToolCalls: [ToolCall] = []
                    // Accumulator for the tool_use block currently being streamed.
                    var currentToolID: String?
                    var currentToolName: String?
                    var currentToolJSON = ""

                    func finishCurrentToolBlock() {
                        guard let id = currentToolID, let name = currentToolName else { return }
                        let inputDict: [String: Any] = {
                            guard !currentToolJSON.isEmpty,
                                  let data = currentToolJSON.data(using: .utf8),
                                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                                return [:]
                            }
                            return obj
                        }()
                        completedToolCalls.append(ToolCall(
                            id: id,
                            toolName: name,
                            input: ToolJSON.input(from: inputDict)
                        ))
                        currentToolID = nil
                        currentToolName = nil
                        currentToolJSON = ""
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = line.dropFirst(6)

                        if let data = jsonStr.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let type = json["type"] as? String {

                            switch type {
                            case "content_block_start":
                                if let block = json["content_block"] as? [String: Any],
                                   block["type"] as? String == "tool_use" {
                                    currentToolID = block["id"] as? String ?? UUID().uuidString
                                    currentToolName = block["name"] as? String
                                    currentToolJSON = ""
                                }
                            case "content_block_delta":
                                if let delta = json["delta"] as? [String: Any] {
                                    if let text = delta["text"] as? String {
                                        continuation.yield(StreamedToken(text: text, tokenIndex: tokenIndex, isFinal: false))
                                        tokenIndex += 1
                                    } else if let partialJSON = delta["partial_json"] as? String {
                                        currentToolJSON += partialJSON
                                    }
                                }
                            case "content_block_stop":
                                finishCurrentToolBlock()
                            case "message_stop":
                                break
                            default:
                                break
                            }
                            if type == "message_stop" { break }
                        }
                    }
                    finishCurrentToolBlock()
                    continuation.yield(StreamedToken(
                        text: "",
                        tokenIndex: tokenIndex,
                        isFinal: true,
                        toolCalls: completedToolCalls.isEmpty ? nil : completedToolCalls
                    ))
                    continuation.finish()
                } catch {
                    claudeGatewayLog.error("Streaming failed: \(error.localizedDescription, privacy: .public)")
                    continuation.finish()
                }
            }
        }
    }

    func executeToolCall(_ call: ToolCall, context: ConversationContext) async throws -> ToolResult {
        // Tool calls requested by the model are executed locally through the
        // ToolRouter; results are fed back to the model by the agent loop.
        await ToolRouter.shared.execute(call)
    }

    func getConfig() async throws -> GatewayConfig {
        return GatewayConfig(supportedModels: ["claude-3-5-sonnet-20240620", "claude-3-haiku-20240307"])
    }

    func listAvailableModels() async throws -> [GatewayModelChoice] {
        return [
            GatewayModelChoice(
                provider: identifier,
                model: "claude-3-5-sonnet-20240620",
                displayName: "Claude 3.5 Sonnet",
                summary: "Anthropic's latest high-performance model"
            ),
            GatewayModelChoice(
                provider: identifier,
                model: "claude-3-haiku-20240307",
                displayName: "Claude 3 Haiku",
                summary: "Fast and lightweight model"
            )
        ]
    }

    func sessionList(limit: Int) async throws -> [SessionSummary] { return [] }
    func branchSession(fromMessageId messageId: String) async throws -> SessionSummary { throw NSError(domain: "Claude", code: 1, userInfo: nil) }
}
