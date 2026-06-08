import Foundation

/// Gateway provider: bridges to external reasoning engines, APIs, or services.
/// Conforming types: HermesGateway, AnthropicGateway, OllamaGateway, OpenAIGateway
///
/// Design: Each gateway abstracts a different reasoning backend.
/// Apps use only this protocol; never the concrete gateway type.
public protocol GatewayProvider: AnyObject, Sendable {
    /// Unique identifier for this gateway.
    /// Examples: "hermes", "anthropic", "ollama", "openai"
    var identifier: String { get }

    /// Human-readable name of the backing service.
    var serviceName: String { get }

    /// What this gateway can do.
    /// Examples: ["reasoning", "streaming", "tools", "vision"]
    var capabilities: Set<String> { get }

    /// Check connectivity to the backing service.
    func healthCheck() async throws -> GatewayHealth

    /// Send a prompt and get a response.
    /// May stream or return all at once depending on backend.
    func prompt(
        _ message: String,
        context: ConversationContext,
        options: GatewayOptions
    ) async throws -> GatewayResponse

    /// Stream a response token-by-token.
    func promptStream(
        _ message: String,
        context: ConversationContext,
        options: GatewayOptions
    ) -> AsyncStream<StreamedToken>

    /// Execute a tool through this gateway.
    /// Gateway may validate, route, or execute directly.
    func executeToolCall(
        _ call: ToolCall,
        context: ConversationContext
    ) async throws -> ToolResult

    /// Get gateway configuration and limits.
    func getConfig() async throws -> GatewayConfig

    /// List recent sessions from this gateway.
    /// Gateways without session support (e.g., Ollama) return an empty array.
    func sessionList(limit: Int) async throws -> [SessionSummary]

    /// Branch (fork) a session from a specific message, creating a new session
    /// that shares history up to that point. Gateways without session support
    /// should throw a descriptive error.
    func branchSession(fromMessageId messageId: String) async throws -> SessionSummary
}

/// Health status of a gateway.
public struct GatewayHealth: Codable, Sendable {
    public let isHealthy: Bool
    public let latencyMs: Double
    public let lastCheckedAt: Date
    public let details: [String: AnyCodable]?

    public init(
        isHealthy: Bool,
        latencyMs: Double = 0,
        lastCheckedAt: Date = Date(),
        details: [String: AnyCodable]? = nil
    ) {
        self.isHealthy = isHealthy
        self.latencyMs = latencyMs
        self.lastCheckedAt = lastCheckedAt
        self.details = details
    }
}

/// Options for gateway requests.
public struct GatewayOptions: Codable, Sendable {
    public let temperature: Double
    public let maxTokens: Int
    public let topP: Double
    public let stopSequences: [String]
    public let systemPrompt: String?
    public let tools: [Tool]?
    public let metadata: [String: AnyCodable]

    public init(
        temperature: Double = 0.7,
        maxTokens: Int = 2000,
        topP: Double = 1.0,
        stopSequences: [String] = [],
        systemPrompt: String? = nil,
        tools: [Tool]? = nil,
        metadata: [String: AnyCodable] = [:]
    ) {
        self.temperature = max(0, min(2, temperature))
        self.maxTokens = max(1, maxTokens)
        self.topP = max(0, min(1, topP))
        self.stopSequences = stopSequences
        self.systemPrompt = systemPrompt
        self.tools = tools
        self.metadata = metadata
    }
}

/// Response from a gateway.
public struct GatewayResponse: Codable, Sendable {
    public let text: String
    public let toolCalls: [ToolCall]
    public let stopReason: StopReason
    public let tokenCount: TokenCount
    public let metadata: [String: AnyCodable]

    public enum StopReason: String, Codable, Sendable {
        case endTurn = "end_turn"
        case maxTokens = "max_tokens"
        case stopSequence = "stop_sequence"
        case toolCall = "tool_call"
    }

    public init(
        text: String,
        toolCalls: [ToolCall] = [],
        stopReason: StopReason = .endTurn,
        tokenCount: TokenCount = TokenCount(),
        metadata: [String: AnyCodable] = [:]
    ) {
        self.text = text
        self.toolCalls = toolCalls
        self.stopReason = stopReason
        self.tokenCount = tokenCount
        self.metadata = metadata
    }
}

/// Streamed token from a gateway.
public struct StreamedToken: Codable, Sendable {
    public let text: String
    public let tokenIndex: Int
    public let isFinal: Bool

    public init(
        text: String,
        tokenIndex: Int = 0,
        isFinal: Bool = false
    ) {
        self.text = text
        self.tokenIndex = tokenIndex
        self.isFinal = isFinal
    }
}

/// Token usage statistics.
public struct TokenCount: Codable, Sendable {
    public let input: Int
    public let output: Int
    public let total: Int

    public init(input: Int = 0, output: Int = 0) {
        self.input = input
        self.output = output
        self.total = input + output
    }

    var cost: Double {
        Double(input) * 0.003 / 1000.0 + Double(output) * 0.015 / 1000.0
    }
}

/// Tool call invoked by gateway.
public struct ToolCall: Codable, Sendable, Equatable {
    public let id: String
    public let toolName: String
    public let input: [String: AnyCodable]

    public init(
        id: String = UUID().uuidString,
        toolName: String,
        input: [String: AnyCodable]
    ) {
        self.id = id
        self.toolName = toolName
        self.input = input
    }
}

/// Gateway configuration and limits.
public struct GatewayConfig: Codable, Sendable {
    public let maxTokensPerRequest: Int
    public let maxRequestsPerMinute: Int
    public let supportedModels: [String]
    public let costPerMillionInputTokens: Double
    public let costPerMillionOutputTokens: Double
    public let supportsStreaming: Bool
    public let supportsToolCalling: Bool
    public let supportsVision: Bool

    public init(
        maxTokensPerRequest: Int = 4096,
        maxRequestsPerMinute: Int = 100,
        supportedModels: [String] = [],
        costPerMillionInputTokens: Double = 3.0,
        costPerMillionOutputTokens: Double = 15.0,
        supportsStreaming: Bool = true,
        supportsToolCalling: Bool = true,
        supportsVision: Bool = false
    ) {
        self.maxTokensPerRequest = maxTokensPerRequest
        self.maxRequestsPerMinute = maxRequestsPerMinute
        self.supportedModels = supportedModels
        self.costPerMillionInputTokens = costPerMillionInputTokens
        self.costPerMillionOutputTokens = costPerMillionOutputTokens
        self.supportsStreaming = supportsStreaming
        self.supportsToolCalling = supportsToolCalling
        self.supportsVision = supportsVision
    }
}
