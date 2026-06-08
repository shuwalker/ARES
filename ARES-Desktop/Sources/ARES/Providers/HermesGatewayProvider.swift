import Foundation
import ARESCore

// MARK: - Hermes Gateway Provider
//
// Conforms to GatewayProvider, wrapping the existing HermesGateway for internal use.
// Hermes becomes a swappable backend through the protocol, not a direct dependency.

final class HermesGatewayProvider: GatewayProvider, @unchecked Sendable {

    private let hermesGateway: HermesGateway

    init(baseURL: URL = URL(string: "http://localhost:8642")!,
         apiKey: String = ProcessInfo.processInfo.environment["API_SERVER_KEY"] ?? "") {
        self.hermesGateway = HermesGateway(baseURL: baseURL, apiKey: apiKey)
    }

    // MARK: - GatewayProvider Protocol

    var identifier: String { "hermes" }
    var serviceName: String { "Hermes Agent" }
    var capabilities: Set<String> { ["reasoning", "streaming", "tools", "sessions"] }

    func healthCheck() async throws -> GatewayHealth {
        let startTime = Date()
        let isHealthy = await hermesGateway.isReachable()
        let elapsed = Date().timeIntervalSince(startTime) * 1000
        return GatewayHealth(isHealthy: isHealthy, latencyMs: elapsed)
    }

    func prompt(
        _ message: String,
        context: ConversationContext,
        options: GatewayOptions
    ) async throws -> GatewayResponse {
        // Collect stream into single response
        var accumulated = ""
        var finalSessionID: String?
        var finalUsage: GatewayUsage?

        let messages = context.messages.map { msg in
            GatewayMessage(role: msg.role.rawValue, content: msg.content)
        }

        for try await token in hermesGateway.streamChat(
            messages: messages,
            sessionID: context.sessionID,
            model: context.model ?? "hermes-agent"
        ) {
            accumulated += token.content
            if token.isFinished {
                finalSessionID = token.sessionID
                finalUsage = token.usage
            }
        }

        return GatewayResponse(
            text: accumulated,
            stopReason: .endTurn,
            tokenCount: TokenCount(
                input: finalUsage?.promptTokens ?? 0,
                output: finalUsage?.completionTokens ?? 0
            )
        )
    }

    func promptStream(
        _ message: String,
        context: ConversationContext,
        options: GatewayOptions
    ) -> AsyncStream<StreamedToken> {
        AsyncStream { (continuation: AsyncStream<StreamedToken>.Continuation) in
            Task {
                let messages = context.messages.map { msg in
                    GatewayMessage(role: msg.role.rawValue, content: msg.content)
                }

                do {
                    for try await token in hermesGateway.streamChat(
                        messages: messages,
                        sessionID: context.sessionID,
                        model: context.model ?? "hermes-agent"
                    ) {
                        continuation.yield(StreamedToken(
                            text: token.content,
                            isFinal: token.isFinished
                        ))

                        if token.isFinished {
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
        // Hermes handles tool execution server-side
        return ToolResult(success: true, data: AnyCodable.string("Tool execution delegated to Hermes"))
    }

    func getConfig() async throws -> GatewayConfig {
        return GatewayConfig(
            maxTokensPerRequest: 4096,
            maxRequestsPerMinute: 100,
            supportedModels: ["hermes-agent"],
            supportsStreaming: true,
            supportsToolCalling: true,
            supportsVision: false
        )
    }

    // MARK: - Session Management

    func sessionList(limit: Int = 20) async throws -> [SessionSummary] {
        let sessions = try await hermesGateway.listSessions(limit: limit)
        return sessions.map { gwSession in
            SessionSummary(
                id: gwSession.id,
                title: gwSession.title,
                model: gwSession.model,
                parentSessionID: nil,
                startedAt: gwSession.startedAt.map { SessionTimestamp.unixSeconds($0) },
                lastActive: gwSession.lastActive.map { SessionTimestamp.unixSeconds($0) },
                messageCount: gwSession.messageCount,
                preview: gwSession.preview
            )
        }
    }

    func branchSession(fromMessageId messageId: String) async throws -> SessionSummary {
        // Create a new session with a title referencing the branch point
        let branched = try await hermesGateway.createSession(title: "Branched from message \(messageId)")
        return SessionSummary(
            id: branched.id,
            title: branched.title,
            model: branched.model,
            parentSessionID: nil,
            startedAt: branched.startedAt.map { SessionTimestamp.unixSeconds($0) },
            lastActive: branched.lastActive.map { SessionTimestamp.unixSeconds($0) },
            messageCount: branched.messageCount,
            preview: branched.preview
        )
    }
}
