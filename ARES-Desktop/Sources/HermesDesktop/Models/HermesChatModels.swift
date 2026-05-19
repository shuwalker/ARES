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

struct ChatMessage: Identifiable, Sendable {
    let id: UUID
    let role: ChatMessageRole
    var content: String
    let timestamp: Date
    var isStreaming: Bool
    var toolCalls: [ChatToolCall]

    init(
        id: UUID = UUID(),
        role: ChatMessageRole,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false,
        toolCalls: [ChatToolCall] = []
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
        self.toolCalls = toolCalls
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
