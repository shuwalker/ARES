import Foundation

// MARK: - Streaming chat models

struct ChatStreamChunk: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        struct Delta: Decodable, Sendable {
            struct ToolCallDelta: Decodable, Sendable {
                struct FunctionDelta: Decodable, Sendable {
                    let name: String?
                    let arguments: String?
                }
                let index: Int?
                let id: String?
                let function: FunctionDelta?
            }
            let content: String?
            let toolCalls: [ToolCallDelta]?

            enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
        }
        struct Message: Decodable, Sendable {
            let content: String?
        }
        let delta: Delta
        let finishReason: String?
        let message: Message?

        enum CodingKeys: String, CodingKey {
            case delta
            case finishReason = "finish_reason"
            case message
        }
    }
    let choices: [Choice]?
    let sessionID: String?

    enum CodingKeys: String, CodingKey {
        case choices
        case sessionID = "session_id"
    }

    var textDelta: String { choices?.first?.delta.content ?? "" }
    var finishReason: String? { choices?.first?.finishReason }
    var toolCallDeltas: [Choice.Delta.ToolCallDelta] { choices?.first?.delta.toolCalls ?? [] }
}

// MARK: - Tool call visualization models

enum ToolCallStatus: Equatable, Sendable {
    case running
    case done
    case failed
}

struct ChatToolCall: Identifiable, Sendable, Equatable {
    let id: String
    var name: String
    var input: String
    var output: String?
    var status: ToolCallStatus
}

enum ChatMessageRole: Equatable, Sendable {
    case user
    case assistant
}

// MARK: - Thinking level

enum ThinkingLevel: String, CaseIterable, Sendable {
    case off = "Off"
    case low = "Low"
    case adaptive = "Adaptive"

    /// budget_tokens value to include in the request body (nil = omit thinking key entirely)
    var budgetTokens: Int? {
        switch self {
        case .off: return nil
        case .low: return 1024
        case .adaptive: return 8000
        }
    }
}

struct ChatMessage: Identifiable, Sendable {
    /// Shared ISO-8601 decoder for Codable conformances that include `Date` fields.
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    let id: UUID
    let role: ChatMessageRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool
    var toolCalls: [ChatToolCall]
    /// Accumulated extended-thinking text, if any
    var thinkingContent: String?
    /// Whether the thinking disclosure group is expanded
    var isThinkingExpanded: Bool

    /// Human-readable time string for this message (e.g. "3:42 PM").
    var formattedTimestamp: String {
        Self.timestampFormatter.string(from: timestamp)
    }

    init(
        id: UUID = UUID(),
        role: ChatMessageRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        toolCalls: [ChatToolCall] = [],
        thinkingContent: String? = nil,
        isThinkingExpanded: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.toolCalls = toolCalls
        self.thinkingContent = thinkingContent
        self.isThinkingExpanded = isThinkingExpanded
    }
}

// MARK: - Existing models

struct HermesChatInvocation: Equatable, Sendable {
    let sessionID: String?
    let prompt: String
    let autoApproveCommands: Bool

    init(sessionID: String?, prompt: String, autoApproveCommands: Bool = false) {
        self.sessionID = sessionID
        self.prompt = prompt
        self.autoApproveCommands = autoApproveCommands
    }

    var arguments: [String] {
        var values = [String]()
        if let sessionID {
            values.append(contentsOf: ["--resume", sessionID])
        }
        if autoApproveCommands {
            values.append("--yolo")
        }
        values.append(contentsOf: [
            "chat",
            "--quiet",
            "--query",
            prompt
        ])
        return values
    }
}

struct HermesSessionResumeInvocation: Equatable, Sendable {
    let sessionID: String
    let hermesProfileName: String?
    let startupCommandLine: String

    init(sessionID: String, connection: ConnectionProfile) {
        self.sessionID = sessionID
        self.hermesProfileName = connection.cliHermesProfileName
        self.startupCommandLine = connection.remoteHermesCommandLine(arguments: Self.buildArguments(
            hermesProfileName: connection.cliHermesProfileName,
            sessionID: sessionID
        ))
    }

    var arguments: [String] {
        Self.buildArguments(
            hermesProfileName: hermesProfileName,
            sessionID: sessionID
        )
    }

    var commandLine: String {
        (["hermes"] + arguments)
            .map(\.shellQuotedForTerminalCommand)
            .joined(separator: " ")
    }

    private static func buildArguments(
        hermesProfileName: String?,
        sessionID: String
    ) -> [String] {
        var values = [String]()
        if let hermesProfileName {
            values.append(contentsOf: ["--profile", hermesProfileName])
        }
        values.append(contentsOf: ["--resume", sessionID])
        return values
    }
}

struct PendingSessionTurn: Identifiable, Equatable, Sendable {
    let id: UUID
    let sessionID: String?
    let prompt: String
    let startedAt: Date
    let autoApproveCommands: Bool

    init(
        id: UUID = UUID(),
        sessionID: String?,
        prompt: String,
        startedAt: Date = Date(),
        autoApproveCommands: Bool
    ) {
        self.id = id
        self.sessionID = sessionID
        self.prompt = prompt
        self.startedAt = startedAt
        self.autoApproveCommands = autoApproveCommands
    }
}

struct HermesChatTurnResult: Codable, Sendable {
    let ok: Bool
    let sessionID: String?
    let stdout: String?
    let stderr: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case sessionID = "session_id"
        case stdout
        case stderr
    }
}

// MARK: - Tool approval models

struct ToolApprovalRequest: Identifiable, Codable, Sendable {
    let id: String
    let toolName: String
    let toolInput: String
    let sessionId: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case sessionId = "session_id"
        case createdAt = "created_at"
    }
}
