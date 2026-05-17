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
