import Foundation

public struct RemoteDiscovery: Codable {
    public let ok: Bool
    public let remoteHome: String
    public let hermesHome: String
    public let activeProfile: RemoteARESProfile
    public let availableProfiles: [RemoteARESProfile]
    public let paths: RemoteARESPaths
    public let exists: RemoteARESPathExistence
    public let sessionStore: RemoteSessionStore?
    public let kanban: RemoteKanbanDiscovery?

    enum CodingKeys: String, CodingKey {
        case ok
        case remoteHome = "remote_home"
        case hermesHome = "hermes_home"
        case activeProfile = "active_profile"
        case availableProfiles = "available_profiles"
        case paths
        case exists
        case sessionStore = "session_store"
        case kanban
    }
}

public struct RemoteARESProfile: Codable, Identifiable {
    public let name: String
    public let path: String
    public let isDefault: Bool
    public let exists: Bool

    public var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case isDefault = "is_default"
        case exists
    }
}

public struct RemoteARESPaths: Codable {
    public let user: String
    public let memory: String
    public let soul: String
    public let sessionsDir: String
    public let cronJobs: String
    public let kanbanDatabase: String?

    enum CodingKeys: String, CodingKey {
        case user
        case memory
        case soul
        case sessionsDir = "sessions_dir"
        case cronJobs = "cron_jobs"
        case kanbanDatabase = "kanban_database"
    }
}

public struct RemoteARESPathExistence: Codable {
    public let user: Bool
    public let memory: Bool
    public let soul: Bool
    public let sessionsDir: Bool
    public let cronJobs: Bool
    public let kanbanDatabase: Bool?

    enum CodingKeys: String, CodingKey {
        case user
        case memory
        case soul
        case sessionsDir = "sessions_dir"
        case cronJobs = "cron_jobs"
        case kanbanDatabase = "kanban_database"
    }
}

public struct RemoteSessionStore: Codable, Sendable {
    public let kind: RemoteSessionStoreKind
    public let path: String
    public let sessionTable: String?
    public let messageTable: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case path
        case sessionTable = "session_table"
        case messageTable = "message_table"
    }
}

public struct RemoteKanbanDiscovery: Codable, Hashable {
    public let databasePath: String
    public let exists: Bool
    public let hostWide: Bool
    public let hasARESCLI: Bool
    public let hasKanbanModule: Bool
    public let dispatcher: KanbanDispatcherStatus?

    enum CodingKeys: String, CodingKey {
        case databasePath = "database_path"
        case exists
        case hostWide = "host_wide"
        case hasARESCLI = "has_hermes_cli"
        case hasKanbanModule = "has_kanban_module"
        case dispatcher
    }
}

public enum RemoteSessionStoreKind: Codable, Hashable, Sendable {
    case sqlite
    case other(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(decodedValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encodedValue)
    }

    public var displayName: String {
        switch self {
        case .sqlite:
            return "SQLite"
        case .other(let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "Unknown" }
            return trimmed.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private init(decodedValue: String) {
        let normalized = decodedValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "sqlite":
            self = .sqlite
        default:
            self = .other(decodedValue)
        }
    }

    private var encodedValue: String {
        switch self {
        case .sqlite:
            return "sqlite"
        case .other(let value):
            return value
        }
    }
}