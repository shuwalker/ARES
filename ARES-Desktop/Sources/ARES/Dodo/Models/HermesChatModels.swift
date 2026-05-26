import Foundation

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

struct HermesTUIInvocation: Equatable, Sendable {
    let sessionID: String?
    let hermesProfileName: String?
    let startupCommandLine: String

    init(sessionID: String?, connection: ConnectionProfile) {
        self.sessionID = sessionID
        self.hermesProfileName = connection.cliHermesProfileName
        self.startupCommandLine = connection.remoteHermesCommandLine(
            arguments: Self.buildArguments(
                hermesProfileName: connection.cliHermesProfileName,
                sessionID: sessionID
            )
        )
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
        sessionID: String?
    ) -> [String] {
        var values = [String]()
        if let hermesProfileName {
            values.append(contentsOf: ["--profile", hermesProfileName])
        }
        values.append("--tui")
        if let sessionID {
            values.append(contentsOf: ["--resume", sessionID])
        }
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

enum HermesChatTransportMode: Equatable, Sendable {
    case native
    case fallback
}

enum HermesPromptKind: String, Equatable, Hashable, Sendable {
    case approval
    case clarify
    case sudo
    case secret
}

struct HermesPromptCard: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    let sessionID: String?
    let requestID: String
    let kind: HermesPromptKind
    var title: String
    var message: String
    var choices: [String]
    var placeholder: String?
    var toolName: String?
    var actionText: String?
    var previewText: String?
}

enum HermesPromptResponse: Equatable, Sendable {
    case approval(Bool)
    case text(String)
}

struct HermesToolActivityCard: Identifiable, Equatable, Hashable, Sendable {
    let id: String
    var title: String
    var status: String
    var detail: String?
    var isRunning: Bool
    var updatedAt: Date
}

struct SessionCompactionNotice: Identifiable, Equatable, Sendable {
    let id: UUID
    let sourceSessionID: String
    let targetSessionID: String

    init(
        id: UUID = UUID(),
        sourceSessionID: String,
        targetSessionID: String
    ) {
        self.id = id
        self.sourceSessionID = sourceSessionID
        self.targetSessionID = targetSessionID
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

enum HermesGatewayHistoryDecoder {
    static func sessionMessages(from result: JSONValue?) -> [SessionMessage] {
        if let items = result?.arrayValue {
            return sessionMessages(from: items)
        }

        if let object = result?.objectValue,
           let nestedItems = object["messages"]?.arrayValue ?? object["items"]?.arrayValue {
            return sessionMessages(from: nestedItems)
        }

        return []
    }

    private static func sessionMessages(from items: [JSONValue]) -> [SessionMessage] {
        items.enumerated().compactMap { index, item in
            guard let object = item.objectValue else { return nil }

            let content = firstString(in: object, keys: ["content", "text", "message"])
            let metadata = metadataPayload(from: object)
            let messageID = firstString(in: object, keys: ["message_id", "id"]) ?? "gateway-\(index)"
            let role = SessionMessageRole(remoteValue: firstString(in: object, keys: ["role"]) ?? "system")

            guard !role.isToolRole else { return nil }
            guard content?.isEmpty == false || metadata?.isEmpty == false else {
                return nil
            }

            return SessionMessage(
                id: messageID,
                role: role,
                content: content,
                timestamp: timestamp(from: object["timestamp"] ?? object["created_at"]),
                metadata: metadata
            )
        }
    }

    private static func metadataPayload(from object: [String: JSONValue]) -> [String: JSONValue]? {
        var metadata = object
        metadata.removeValue(forKey: "message_id")
        metadata.removeValue(forKey: "id")
        metadata.removeValue(forKey: "role")
        metadata.removeValue(forKey: "content")
        metadata.removeValue(forKey: "text")
        metadata.removeValue(forKey: "message")
        metadata.removeValue(forKey: "timestamp")
        metadata.removeValue(forKey: "created_at")
        return metadata.isEmpty ? nil : metadata
    }

    private static func timestamp(from value: JSONValue?) -> SessionTimestamp? {
        switch value {
        case .int(let seconds):
            return .unixSeconds(Double(seconds))
        case .number(let seconds):
            return .unixSeconds(seconds)
        case .string(let text):
            return .text(text)
        default:
            return nil
        }
    }

    private static func firstString(
        in object: [String: JSONValue],
        keys: [String]
    ) -> String? {
        for key in keys {
            let value = object[key]
            let text = value?.stringValue ?? value?.displayString
            guard let text else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }
}
