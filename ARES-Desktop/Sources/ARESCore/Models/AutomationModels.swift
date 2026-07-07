import Foundation

// MARK: - Automation

/// A runnable script discovered on the local filesystem (e.g. in ~/.hermes/scripts/).
/// This is NOT a cron job (which schedules things) and NOT a workflow (which is a prompt preset).
/// An Automation is the script itself — its source, its runtime status, its logs, its state files.
public struct Automation: Identifiable, Hashable, Sendable {
    public let id: String
    public let filename: String
    public let filePath: String
    public let language: AutomationLanguage
    public let name: String
    public let description: String?
    public let lastModified: Date?
    public let fileSize: Int64?

    /// Companion files found alongside the script (logs, state JSON, etc).
    public let companionFiles: [AutomationCompanionFile]

    /// Runtime status detected at scan time.
    public var status: AutomationStatus

    /// PID of the running process, if any.
    public var runningPID: Int32?

    public init(
        id: String = UUID().uuidString,
        filename: String,
        filePath: String,
        language: AutomationLanguage,
        name: String,
        description: String? = nil,
        lastModified: Date? = nil,
        fileSize: Int64? = nil,
        companionFiles: [AutomationCompanionFile] = [],
        status: AutomationStatus = .unknown,
        runningPID: Int32? = nil
    ) {
        self.id = id
        self.filename = filename
        self.filePath = filePath
        self.language = language
        self.name = name
        self.description = description
        self.lastModified = lastModified
        self.fileSize = fileSize
        self.companionFiles = companionFiles
        self.status = status
        self.runningPID = runningPID
    }

    // MARK: - Derived

    public var displayLanguage: String {
        switch language {
        case .python: return "Python"
        case .shell:  return "Shell"
        }
    }

    public var fileExtension: String {
        switch language {
        case .python: return ".py"
        case .shell:  return ".sh"
        }
    }

    /// Short status label for badges.
    public var statusLabel: String {
        switch status {
        case .running: return "Running"
        case .stopped:  return "Stopped"
        case .idle:     return "Idle"
        case .error:    return "Error"
        case .unknown:  return "Unknown"
        }
    }

    public var isActive: Bool { status == .running }

    // MARK: - Search

    public func matchesSearch(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let normalized = trimmed.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let searchable = [name, filename, filePath, description ?? ""]
            .map { $0.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
        return searchable.contains { $0.localizedStandardContains(normalized) }
    }
}

// MARK: - Language

public enum AutomationLanguage: String, Codable, Sendable, CaseIterable {
    case python
    case shell
}

// MARK: - Status

public enum AutomationStatus: String, Codable, Sendable {
    case running
    case stopped
    case idle
    case error
    case unknown
}

// MARK: - Companion File

public struct AutomationCompanionFile: Identifiable, Hashable, Sendable {
    public let id: String
    public let filename: String
    public let filePath: String
    public let kind: AutomationCompanionKind
    public let fileSize: Int64?
    public let lastModified: Date?

    public init(
        id: String = UUID().uuidString,
        filename: String,
        filePath: String,
        kind: AutomationCompanionKind,
        fileSize: Int64? = nil,
        lastModified: Date? = nil
    ) {
        self.id = id
        self.filename = filename
        self.filePath = filePath
        self.kind = kind
        self.fileSize = fileSize
        self.lastModified = lastModified
    }
}

// MARK: - Companion Kind

public enum AutomationCompanionKind: String, Codable, Sendable {
    case log
    case state
    case config
    case other

    public var displayLabel: String {
        switch self {
        case .log:    return "Log"
        case .state:  return "State"
        case .config: return "Config"
        case .other:  return "File"
        }
    }

    public var systemImage: String {
        switch self {
        case .log:    return "doc.text"
        case .state:  return "internaldrive"
        case .config: return "slider.horizontal.3"
        case .other:  return "doc"
        }
    }

    /// Classify a companion file by its extension.
    public static func classify(filename: String) -> AutomationCompanionKind {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "log": return .log
        case "json", "toml", "yaml", "yml", "plist", "ini", "conf": return .state
        case "cfg", "rc": return .config
        default: return .other
        }
    }
}