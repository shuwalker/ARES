import Foundation

/// No-op GatewayProvider for testing. Returns echo responses.
public final class DummyGatewayProvider: GatewayProvider, @unchecked Sendable {
    public let identifier = "dummy_gateway"
    public let serviceName = "Dummy Gateway"
    public var capabilities: Set<String> { ["reasoning", "streaming"] }

    public init() {}

    public func healthCheck() async throws -> GatewayHealth {
        GatewayHealth(isHealthy: true, latencyMs: 0)
    }

    public func prompt(_ message: String, context: ConversationContext, options: GatewayOptions) async throws -> GatewayResponse {
        print("🤖 [DUMMY] Gateway prompt: \(message.prefix(40))")
        return GatewayResponse(text: "🤖 Echo: \(message)")
    }

    public func promptStream(_ message: String, context: ConversationContext, options: GatewayOptions) -> AsyncStream<StreamedToken> {
        let words = message.split(separator: " ")
        return AsyncStream { continuation in
            Task {
                for (i, word) in words.enumerated() {
                    continuation.yield(StreamedToken(text: "\(word) ", tokenIndex: i, isFinal: i == words.count - 1))
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
                continuation.finish()
            }
        }
    }

    public func executeToolCall(_ call: ToolCall, context: ConversationContext) async throws -> ToolResult {
        print("🤖 [DUMMY] ToolCall: \(call.toolName)")
        return ToolResult(success: true)
    }

    public func getConfig() async throws -> GatewayConfig {
        GatewayConfig()
    }

    public func listAvailableModels() async throws -> [GatewayModelChoice] {
        return [
            GatewayModelChoice(
                provider: "dummy",
                model: "dummy-model",
                displayName: "Dummy Model",
                summary: "A dummy model for testing."
            )
        ]
    }

    public func sessionList(limit: Int) async throws -> [SessionSummary] {
        // Dummy gateway has no sessions
        return []
    }

    public func branchSession(fromMessageId messageId: String) async throws -> SessionSummary {
        // Dummy gateway cannot branch sessions
        throw DummyGatewayError.unsupportedOperation("Dummy gateway does not support session branching")
    }
}

enum DummyGatewayError: LocalizedError {
    case unsupportedOperation(String)
    var errorDescription: String? {
        switch self {
        case .unsupportedOperation(let msg): return msg
        }
    }
}
