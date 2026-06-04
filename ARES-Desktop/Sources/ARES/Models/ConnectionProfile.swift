import Foundation

struct ConnectionProfile: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var label: String
    var sshAlias: String
    var sshHost: String
    var sshPort: Int?
    var sshUser: String
    var hermesProfile: String?
    var customARESHomePath: String?
    var createdAt: Date
    var updatedAt: Date
    var lastConnectedAt: Date?

    init(
        id: UUID = UUID(),
        label: String = "",
        sshAlias: String = "",
        sshHost: String = "",
        sshPort: Int? = nil,
        sshUser: String = "",
        hermesProfile: String? = nil,
        customARESHomePath: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.sshAlias = sshAlias
        self.sshHost = sshHost
        self.sshPort = sshPort
        self.sshUser = sshUser
        self.hermesProfile = hermesProfile
        self.customARESHomePath = customARESHomePath
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastConnectedAt = lastConnectedAt
    }

    var trimmedAlias: String? {
        let value = sshAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var trimmedHost: String? {
        let value = sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var trimmedUser: String? {
        let value = sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var trimmedARESProfile: String? {
        guard let hermesProfile else { return nil }
        let value = hermesProfile.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        guard value.caseInsensitiveCompare("default") != .orderedSame else { return nil }
        return value
    }

    var trimmedCustomARESHomePath: String? {
        guard let customARESHomePath else { return nil }
        let value = customARESHomePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return value.normalizedCustomARESHomePath
    }

    var usesCustomARESHome: Bool {
        trimmedCustomARESHomePath != nil
    }

    var resolvedARESProfileName: String {
        if let trimmedCustomARESHomePath {
            return trimmedCustomARESHomePath.displayNameForCustomARESHomePath
        }
        return trimmedARESProfile ?? "default"
    }

    var usesDefaultARESProfile: Bool {
        !usesCustomARESHome && trimmedARESProfile == nil
    }

    var cliARESProfileName: String? {
        guard !usesCustomARESHome else { return nil }
        return trimmedARESProfile
    }

    var remoteARESHomePath: String {
        if let trimmedCustomARESHomePath {
            return trimmedCustomARESHomePath
        }
        if let trimmedARESProfile {
            return "~/.hermes/profiles/\(trimmedARESProfile)"
        }

        return "~/.hermes"
    }

    var remoteSkillsPath: String {
        "\(remoteARESHomePath)/skills"
    }

    var remoteCronJobsPath: String {
        "\(remoteARESHomePath)/cron/jobs.json"
    }

    var remoteKanbanHomePath: String {
        "~/.hermes"
    }

    var remoteKanbanDatabasePath: String {
        "\(remoteKanbanHomePath)/kanban.db"
    }

    func remotePath(for trackedFile: RemoteTrackedFile) -> String {
        "\(remoteARESHomePath)/\(trackedFile.relativePathFromARESHome)"
    }

    func applyingARESProfile(named profileName: String) -> ConnectionProfile {
        var copy = self
        copy.hermesProfile = profileName
        copy.customARESHomePath = nil
        return copy.updated()
    }

    var remoteARESHomeShellExpression: String {
        if let trimmedCustomARESHomePath {
            return trimmedCustomARESHomePath.customARESHomeShellExpression
        }
        if let trimmedARESProfile {
            let escapedProfile = trimmedARESProfile.escapedForDoubleQuotedShellArgument
            return "$HOME/.hermes/profiles/\(escapedProfile)"
        }

        return "$HOME/.hermes"
    }

    var remoteARESSearchPathShellExpression: String {
        let entries = [
            "\(remoteARESHomeShellExpression)/hermes-agent/venv/bin",
            "$HOME/.local/bin",
            "$HOME/.hermes/hermes-agent/venv/bin",
            "$HOME/.cargo/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "$PATH"
        ]

        var orderedEntries = [String]()
        var seen = Set<String>()
        for entry in entries where seen.insert(entry).inserted {
            orderedEntries.append(entry)
        }
        return orderedEntries.joined(separator: ":")
    }

    var remoteARESCommandPrefix: String {
        """
        if [ -x "$HERMES_HOME/hermes-agent/venv/bin/hermes" ]; then HERMES_BIN="$HERMES_HOME/hermes-agent/venv/bin/hermes"; elif [ -x "$HOME/.local/bin/hermes" ]; then HERMES_BIN="$HOME/.local/bin/hermes"; elif [ -x "$HOME/.hermes/hermes-agent/venv/bin/hermes" ]; then HERMES_BIN="$HOME/.hermes/hermes-agent/venv/bin/hermes"; elif command -v hermes >/dev/null 2>&1; then HERMES_BIN="$(command -v hermes)"; else printf 'ARES CLI not found.\\n' >&2; exit 127; fi; "$HERMES_BIN"
        """
    }

    func remoteARESCommandLine(arguments: [String]) -> String {
        let quotedArguments = arguments.map(\.shellQuotedForTerminalCommand).joined(separator: " ")
        guard !quotedArguments.isEmpty else { return remoteARESCommandPrefix }
        return "\(remoteARESCommandPrefix) \(quotedArguments)"
    }

    func remoteServiceCommand(_ commandLine: String) -> String {
        let exportCommand = "export HERMES_HOME=\"\(remoteARESHomeShellExpression)\""
        let pathCommand = "export PATH=\"\(remoteARESSearchPathShellExpression)\""
        let escapedCommand = commandLine.escapedForDoubleQuotedShellArgument
        let innerCommand = "\(exportCommand); \(pathCommand); exec /bin/sh -c \"\(escapedCommand)\""
        return "exec /bin/sh -c \"\(innerCommand.escapedForOuterDoubleQuotedShellCommand)\""
    }

    var remoteShellBootstrapCommand: String {
        remoteShellBootstrapCommand()
    }

    func remoteShellBootstrapCommand(startupCommandLine: String? = nil) -> String {
        let exportCommand = "export HERMES_HOME=\"\(remoteARESHomeShellExpression)\""
        let pathCommand = "export PATH=\"\(remoteARESSearchPathShellExpression)\""

        let innerCommand: String
        if let startupCommandLine,
           !startupCommandLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let startupSequence = """
\(startupCommandLine); hermes_bootstrap_exit_code=$?; if [ "$hermes_bootstrap_exit_code" -ne 0 ]; then printf '\\n[ARES Desktop] Startup command exited with status %s.\\n' "$hermes_bootstrap_exit_code"; fi; exec "${SHELL:-/bin/zsh}" -l
"""
            let escapedStartupCommand = startupSequence.escapedForDoubleQuotedShellArgument
            innerCommand = "\(exportCommand); \(pathCommand); exec \"${SHELL:-/bin/zsh}\" -lc \"\(escapedStartupCommand)\""
        } else {
            innerCommand = "\(exportCommand); \(pathCommand); exec \"${SHELL:-/bin/zsh}\" -l"
        }

        return "exec /bin/sh -c \"\(innerCommand.escapedForOuterDoubleQuotedShellCommand)\""
    }

    var workspaceScopeFingerprint: String {
        [
            effectiveTarget,
            trimmedUser ?? "",
            resolvedPort.map(String.init) ?? "",
            remoteARESHomePath
        ].joined(separator: "|")
    }

    var hostConnectionFingerprint: String {
        [
            effectiveTarget,
            trimmedUser ?? "",
            resolvedPort.map(String.init) ?? ""
        ].joined(separator: "|")
    }

    var effectiveTarget: String {
        trimmedAlias ?? trimmedHost ?? ""
    }

    var usesAliasSourceOfTruth: Bool {
        trimmedAlias != nil && trimmedHost == nil
    }

    var resolvedPort: Int? {
        guard let sshPort, sshPort > 0 else { return nil }
        if usesAliasSourceOfTruth && sshPort == 22 {
            return nil
        }
        return sshPort
    }

    var displayDestination: String {
        guard let user = trimmedUser else {
            return effectiveTarget
        }
        return "\(user)@\(effectiveTarget)"
    }

    var isValid: Bool {
        validationError == nil
    }

    var validationError: String? {
        if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Name is required."
        }

        return sshValidationError
    }

    var sshValidationError: String? {
        guard !effectiveTarget.isEmpty else {
            return "Add an SSH alias or host."
        }

        if let error = validateSSHArgument(trimmedAlias, fieldName: "SSH alias") {
            return error
        }

        if let error = validateSSHArgument(trimmedHost, fieldName: "Host") {
            return error
        }

        if let error = validateSSHArgument(trimmedUser, fieldName: "SSH user") {
            return error
        }

        if trimmedARESProfile != nil && trimmedCustomARESHomePath != nil {
            return "Choose either a ARES profile or a custom ARES home path."
        }

        if let trimmedARESProfile {
            if trimmedARESProfile.contains("/") || trimmedARESProfile == "." || trimmedARESProfile == ".." {
                return "ARES profile must be a profile name, not a path."
            }
            if trimmedARESProfile.containsControlCharacter {
                return "ARES profile contains unsupported control characters."
            }
        }

        if let trimmedCustomARESHomePath {
            if trimmedCustomARESHomePath.containsControlCharacter {
                return "Custom ARES home contains unsupported control characters."
            }
            if !trimmedCustomARESHomePath.isValidCustomARESHomePath {
                return "Custom ARES home must start with `~/` or `/`."
            }
        }

        return nil
    }

    func updated() -> ConnectionProfile {
        var copy = self
        copy.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.sshAlias = sshAlias.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.sshHost = sshHost.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.sshUser = sshUser.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.hermesProfile = trimmedARESProfile
        copy.customARESHomePath = trimmedCustomARESHomePath
        if let sshPort = sshPort, sshPort <= 0 {
            copy.sshPort = nil
        }
        copy.updatedAt = Date()
        return copy
    }
}

private extension String {
    var normalizedCustomARESHomePath: String {
        if self == "/" || self == "~" {
            return self
        }
        if self == "~/" {
            return "~"
        }

        var trimmed = self
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    var isValidCustomARESHomePath: Bool {
        self == "~" || hasPrefix("~/") || hasPrefix("/")
    }

    var customARESHomeShellExpression: String {
        if self == "~" {
            return "$HOME"
        }
        if hasPrefix("~/") {
            let suffix = String(dropFirst(2)).escapedForDoubleQuotedShellArgument
            return "$HOME/\(suffix)"
        }
        return escapedForDoubleQuotedShellArgument
    }

    var displayNameForCustomARESHomePath: String {
        let trimmed = normalizedCustomARESHomePath
        if trimmed == "~" || trimmed == "/" {
            return trimmed
        }

        return trimmed.split(separator: "/").last.map(String.init) ?? trimmed
    }

    var escapedForDoubleQuotedShellArgument: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
    }

    var escapedForOuterDoubleQuotedShellCommand: String {
        replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "$", with: "\\$")
            .replacingOccurrences(of: "`", with: "\\`")
    }

    var containsControlCharacter: Bool {
        unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}

private func validateSSHArgument(_ value: String?, fieldName: String) -> String? {
    guard let value else { return nil }
    if value.hasPrefix("-") {
        return "\(fieldName) cannot start with a dash."
    }
    if value.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) || CharacterSet.controlCharacters.contains($0) }) {
        return "\(fieldName) cannot contain whitespace or control characters."
    }
    return nil
}
