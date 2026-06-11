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
    var capabilities: Set<String> { ["reasoning", "streaming", "tools"] }

    func healthCheck() async throws -> GatewayHealth {
        guard !apiKey.isEmpty else {
            return GatewayHealth(isHealthy: false, latencyMs: 0)
        }
        // Actually ping the /models endpoint instead of fabricating latency
        let start = CFAbsoluteTimeGetCurrent()
        let modelsURL = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let elapsed = CFAbsoluteTimeGetCurrent() - start
            let ms = elapsed * 1000.0
            let isHealthy = (response as? HTTPURLResponse)?.statusCode == 200
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
                    let messages = context.messages.map { msg -> [String: String] in
                        ["role": msg.role.rawValue, "content": msg.content]
                    }

                    var body: [String: Any] = [
                        "model": context.model ?? "gpt-4o",
                        "messages": messages,
                        "stream": true,
                        "temperature": options.temperature
                    ]
                    if let tools = options.tools, !tools.isEmpty {
                        body["tools"] = GatewayToolEncoding.openAIFunction(tools)
                    }

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
                    // Tool-call deltas accumulate by index: id + name arrive first,
                    // arguments stream as partial JSON strings.
                    var toolCallAccumulators: [Int: (id: String, name: String, arguments: String)] = [:]

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonStr = line.dropFirst(6)
                        guard jsonStr != "[DONE]" else { break }

                        guard let data = jsonStr.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let first = choices.first,
                              let delta = first["delta"] as? [String: Any] else { continue }

                        if let content = delta["content"] as? String {
                            continuation.yield(StreamedToken(text: content, tokenIndex: tokenIndex, isFinal: false))
                            tokenIndex += 1
                        }

                        if let toolDeltas = delta["tool_calls"] as? [[String: Any]] {
                            for toolDelta in toolDeltas {
                                let index = toolDelta["index"] as? Int ?? 0
                                var acc = toolCallAccumulators[index] ?? (id: "", name: "", arguments: "")
                                if let id = toolDelta["id"] as? String { acc.id = id }
                                if let function = toolDelta["function"] as? [String: Any] {
                                    if let name = function["name"] as? String { acc.name += name }
                                    if let args = function["arguments"] as? String { acc.arguments += args }
                                }
                                toolCallAccumulators[index] = acc
                            }
                        }
                    }

                    let completedToolCalls: [ToolCall] = toolCallAccumulators
                        .sorted { $0.key < $1.key }
                        .compactMap { _, acc in
                            guard !acc.name.isEmpty else { return nil }
                            let inputDict: [String: Any] = {
                                guard !acc.arguments.isEmpty,
                                      let data = acc.arguments.data(using: .utf8),
                                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                                    return [:]
                                }
                                return obj
                            }()
                            return ToolCall(
                                id: acc.id.isEmpty ? UUID().uuidString : acc.id,
                                toolName: acc.name,
                                input: ToolJSON.input(from: inputDict)
                            )
                        }

                    continuation.yield(StreamedToken(
                        text: "",
                        tokenIndex: tokenIndex,
                        isFinal: true,
                        toolCalls: completedToolCalls.isEmpty ? nil : completedToolCalls
                    ))
                    continuation.finish()
                } catch {
                    openAIGatewayLog.error("Streaming failed: \(error.localizedDescription, privacy: .public)")
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
        return GatewayConfig(supportedModels: ["gpt-4o", "gpt-4-turbo", "gpt-3.5-turbo"])
    }

    func listAvailableModels() async throws -> [GatewayModelChoice] {
        guard !apiKey.isEmpty else { return [] }
        
        let modelsURL = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: modelsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [] }
        
        struct OpenAIModelsResponse: Codable {
            let data: [Model]
            struct Model: Codable {
                let id: String
            }
        }
        
        let decoded = try JSONDecoder().decode(OpenAIModelsResponse.self, from: data)
        return decoded.data
            .filter { $0.id.hasPrefix("gpt-") || $0.id.hasPrefix("o1-") }
            .map {
                GatewayModelChoice(
                    provider: identifier,
                    model: $0.id,
                    displayName: $0.id,
                    summary: "OpenAI Model"
                )
            }
    }

    func sessionList(limit: Int) async throws -> [SessionSummary] { return [] }
    func branchSession(fromMessageId messageId: String) async throws -> SessionSummary { throw NSError(domain: "OpenAI", code: 1, userInfo: nil) }
}
