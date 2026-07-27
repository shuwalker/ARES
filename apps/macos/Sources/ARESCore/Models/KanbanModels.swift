import Foundation

public struct KanbanBoardResponse: Codable, Sendable {
    public let ok: Bool
    public let board: KanbanBoard
}

public struct KanbanBoardsResponse: Codable, Sendable {
    public let ok: Bool?
    public let boards: [KanbanProject]
    public let current: String?
    public let supportsBoardManagement: Bool

    enum CodingKeys: String, CodingKey {
        case ok
        case boards
        case current
        case supportsBoardManagement = "supports_board_management"
    }

    public init(ok: Bool? = nil, boards: [KanbanProject], current: String?, supportsBoardManagement: Bool = false) {
        self.ok = ok
        self.boards = boards
        self.current = current
        self.supportsBoardManagement = supportsBoardManagement
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ok = try container.decodeIfPresent(Bool.self, forKey: .ok)
        boards = try container.decodeIfPresent([KanbanProject].self, forKey: .boards) ?? []
        current = try container.decodeIfPresent(String.self, forKey: .current)
        supportsBoardManagement = try container.decodeIfPresent(Bool.self, forKey: .supportsBoardManagement) ?? false
    }
}

public struct KanbanTaskDetailResponse: Codable, Sendable {
    public let ok: Bool
    public let detail: KanbanTaskDetail
}

public struct KanbanBoardOperationResponse: Codable, Sendable {
    public let ok: Bool?
    public let board: KanbanProject?
    public let boards: [KanbanProject]?
    public let current: String?
    public let result: JSONValue?
    public let message: String?
}

public struct KanbanOperationResponse: Codable, Sendable {
    public let ok: Bool
    public let message: String?
    public let taskID: String?
    public let detail: KanbanTaskDetail?
    public let dispatch: KanbanDispatchResult?

    enum CodingKeys: String, CodingKey {
        case ok
        case message
        case taskID = "task_id"
        case detail
        case dispatch
    }
}

public struct KanbanProject: Codable, Identifiable, Hashable, Sendable {
    public static let defaultSlug = "default"

    public let slug: String
    public let name: String?
    public let description: String?
    public let icon: String?
    public let color: String?
    public let createdAt: Int?
    public let archived: Bool
    public let databasePath: String?
    public let isCurrent: Bool
    public let counts: [String: Int]
    public let total: Int?

    enum CodingKeys: String, CodingKey {
        case slug
        case name
        case description
        case icon
        case color
        case createdAt = "created_at"
        case archived
        case databasePath = "db_path"
        case isCurrent = "is_current"
        case counts
        case total
    }

    public init(
        slug: String,
        name: String? = nil,
        description: String? = nil,
        icon: String? = nil,
        color: String? = nil,
        createdAt: Int? = nil,
        archived: Bool = false,
        databasePath: String? = nil,
        isCurrent: Bool = false,
        counts: [String: Int] = [:],
        total: Int? = nil
    ) {
        self.slug = slug
        self.name = name
        self.description = description
        self.icon = icon
        self.color = color
        self.createdAt = createdAt
        self.archived = archived
        self.databasePath = databasePath
        self.isCurrent = isCurrent
        self.counts = counts
        self.total = total
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = try container.decode(String.self, forKey: .slug)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        icon = try container.decodeIfPresent(String.self, forKey: .icon)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        createdAt = try container.decodeIfPresent(Int.self, forKey: .createdAt)
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        databasePath = try container.decodeIfPresent(String.self, forKey: .databasePath)
        isCurrent = try container.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? false
        counts = try container.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
        total = try container.decodeIfPresent(Int.self, forKey: .total)
    }

    public var id: String { slug }

    public var isDefault: Bool {
        slug == Self.defaultSlug
    }

    public var resolvedName: String {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmedName.isEmpty {
            return trimmedName
        }
        if isDefault {
            return L10n.string("Default")
        }
        return slug
            .replacingOccurrences(of: "_", with: "-")
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    public var resolvedIcon: String {
        let trimmedIcon = icon?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedIcon.isEmpty ? "rectangle.3.group" : trimmedIcon
    }

    public var resolvedDescription: String? {
        let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    public var taskTotal: Int {
        total ?? counts.values.reduce(0, +)
    }

    public var createdDate: Date? {
        createdAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }
}

public struct KanbanBoard: Codable, Hashable, Sendable {
    public let databasePath: String
    public let hostWide: Bool
    public let isInitialized: Bool
    public let hasKanbanModule: Bool
    public let hasARESCLI: Bool
    public let dispatcher: KanbanDispatcherStatus?
    public let latestEventID: Int?
    public let warning: String?
    public let tasks: [KanbanTask]
    public let assignees: [KanbanAssignee]
    public let tenants: [String]
    public let stats: KanbanStats?

    enum CodingKeys: String, CodingKey {
        case databasePath = "database_path"
        case hostWide = "host_wide"
        case isInitialized = "is_initialized"
        case hasKanbanModule = "has_kanban_module"
        case hasARESCLI = "has_hermes_cli"
        case dispatcher
        case latestEventID = "latest_event_id"
        case warning
        case tasks
        case assignees
        case tenants
        case stats
    }

    public static let empty = KanbanBoard(
        databasePath: "~/.hermes/kanban.db",
        hostWide: true,
        isInitialized: false,
        hasKanbanModule: false,
        hasARESCLI: false,
        dispatcher: nil,
        latestEventID: nil,
        warning: nil,
        tasks: [],
        assignees: [],
        tenants: [],
        stats: nil
    )

    public var visibleStatuses: [KanbanTaskStatus] {
        KanbanTaskStatus.boardStatuses.filter { status in
            status != .archived || tasks.contains(where: { $0.status == .archived })
        }
    }

    public func tasks(for status: KanbanTaskStatus) -> [KanbanTask] {
        tasks.filter { $0.status == status }
    }

    public func task(id: String?) -> KanbanTask? {
        guard let id else { return nil }
        return tasks.first(where: { $0.id == id })
    }
}

public struct KanbanTask: Codable, Identifiable, Hashable, Sendable, TitleIdentifiable {
    public let id: String
    public let title: String?
    public let body: String?
    public let assignee: String?
    public let status: KanbanTaskStatus
    public let priority: Int
    public let createdBy: String?
    public let createdAt: Int?
    public let startedAt: Int?
    public let completedAt: Int?
    public let workspaceKind: KanbanWorkspaceKind
    public let workspacePath: String?
    public let tenant: String?
    public let result: String?
    public let skills: [String]
    public let spawnFailures: Int
    public let workerPID: Int?
    public let lastSpawnError: String?
    public let maxRuntimeSeconds: Int?
    public let maxRetries: Int?
    public let lastHeartbeatAt: Int?
    public let currentRunID: Int?
    public let parentIDs: [String]
    public let childIDs: [String]
    public let progress: KanbanTaskProgress?
    public let commentCount: Int
    public let eventCount: Int
    public let runCount: Int
    public let latestEventAt: Int?
    public let warnings: KanbanTaskWarnings?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case body
        case assignee
        case status
        case priority
        case createdBy = "created_by"
        case createdAt = "created_at"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case workspaceKind = "workspace_kind"
        case workspacePath = "workspace_path"
        case tenant
        case result
        case skills
        case spawnFailures = "spawn_failures"
        case workerPID = "worker_pid"
        case lastSpawnError = "last_spawn_error"
        case maxRuntimeSeconds = "max_runtime_seconds"
        case maxRetries = "max_retries"
        case lastHeartbeatAt = "last_heartbeat_at"
        case currentRunID = "current_run_id"
        case parentIDs = "parent_ids"
        case childIDs = "child_ids"
        case progress
        case commentCount = "comment_count"
        case eventCount = "event_count"
        case runCount = "run_count"
        case latestEventAt = "latest_event_at"
        case warnings
    }

    public init(
        id: String,
        title: String?,
        body: String?,
        assignee: String?,
        status: KanbanTaskStatus,
        priority: Int,
        createdBy: String?,
        createdAt: Int?,
        startedAt: Int?,
        completedAt: Int?,
        workspaceKind: KanbanWorkspaceKind,
        workspacePath: String?,
        tenant: String?,
        result: String?,
        skills: [String],
        spawnFailures: Int,
        workerPID: Int?,
        lastSpawnError: String?,
        maxRuntimeSeconds: Int?,
        maxRetries: Int?,
        lastHeartbeatAt: Int?,
        currentRunID: Int?,
        parentIDs: [String],
        childIDs: [String],
        progress: KanbanTaskProgress?,
        commentCount: Int,
        eventCount: Int,
        runCount: Int,
        latestEventAt: Int?,
        warnings: KanbanTaskWarnings? = nil
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.assignee = assignee
        self.status = status
        self.priority = priority
        self.createdBy = createdBy
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.workspaceKind = workspaceKind
        self.workspacePath = workspacePath
        self.tenant = tenant
        self.result = result
        self.skills = skills
        self.spawnFailures = spawnFailures
        self.workerPID = workerPID
        self.lastSpawnError = lastSpawnError
        self.maxRuntimeSeconds = maxRuntimeSeconds
        self.maxRetries = maxRetries
        self.lastHeartbeatAt = lastHeartbeatAt
        self.currentRunID = currentRunID
        self.parentIDs = parentIDs
        self.childIDs = childIDs
        self.progress = progress
        self.commentCount = commentCount
        self.eventCount = eventCount
        self.runCount = runCount
        self.latestEventAt = latestEventAt
        self.warnings = warnings
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        assignee = try container.decodeIfPresent(String.self, forKey: .assignee)
        status = try container.decodeIfPresent(KanbanTaskStatus.self, forKey: .status) ?? .other("unknown")
        priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        createdBy = try container.decodeIfPresent(String.self, forKey: .createdBy)
        createdAt = try container.decodeIfPresent(Int.self, forKey: .createdAt)
        startedAt = try container.decodeIfPresent(Int.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Int.self, forKey: .completedAt)
        workspaceKind = try container.decodeIfPresent(KanbanWorkspaceKind.self, forKey: .workspaceKind) ?? .scratch
        workspacePath = try container.decodeIfPresent(String.self, forKey: .workspacePath)
        tenant = try container.decodeIfPresent(String.self, forKey: .tenant)
        result = try container.decodeIfPresent(String.self, forKey: .result)
        skills = try container.decodeIfPresent([String].self, forKey: .skills) ?? []
        spawnFailures = try container.decodeIfPresent(Int.self, forKey: .spawnFailures) ?? 0
        workerPID = try container.decodeIfPresent(Int.self, forKey: .workerPID)
        lastSpawnError = try container.decodeIfPresent(String.self, forKey: .lastSpawnError)
        maxRuntimeSeconds = try container.decodeIfPresent(Int.self, forKey: .maxRuntimeSeconds)
        maxRetries = try container.decodeIfPresent(Int.self, forKey: .maxRetries)
        lastHeartbeatAt = try container.decodeIfPresent(Int.self, forKey: .lastHeartbeatAt)
        currentRunID = try container.decodeIfPresent(Int.self, forKey: .currentRunID)
        parentIDs = try container.decodeIfPresent([String].self, forKey: .parentIDs) ?? []
        childIDs = try container.decodeIfPresent([String].self, forKey: .childIDs) ?? []
        progress = try container.decodeIfPresent(KanbanTaskProgress.self, forKey: .progress)
        commentCount = try container.decodeIfPresent(Int.self, forKey: .commentCount) ?? 0
        eventCount = try container.decodeIfPresent(Int.self, forKey: .eventCount) ?? 0
        runCount = try container.decodeIfPresent(Int.self, forKey: .runCount) ?? 0
        latestEventAt = try container.decodeIfPresent(Int.self, forKey: .latestEventAt)
        warnings = try container.decodeIfPresent(KanbanTaskWarnings.self, forKey: .warnings)
    }

    public var resolvedTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? id : trimmed
    }

    public var trimmedBody: String? {
        trimmedText(body)
    }

    public var trimmedResult: String? {
        trimmedText(result)
    }

    public var createdDate: Date? {
        createdAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    public var latestActivityDate: Date? {
        (latestEventAt ?? completedAt ?? startedAt ?? createdAt)
            .map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    public var isRunning: Bool {
        status == .running
    }

    public var hasActiveWarnings: Bool {
        warnings?.hasWarnings == true
    }

    public var isBlocked: Bool {
        status == .blocked
    }

    public var isTerminal: Bool {
        status == .done || status == .archived
    }

    public var canBlock: Bool {
        status == .ready || status == .running
    }

    public var canComplete: Bool {
        status == .ready || status == .running || status == .blocked
    }

    public var canUnblock: Bool {
        status == .blocked
    }

    public var canSpecify: Bool {
        status == .triage
    }

    public var priorityLabel: String {
        if priority > 0 {
            return "P+\(priority)"
        }
        if priority < 0 {
            return "P\(priority)"
        }
        return "P0"
    }

    public var progressLabel: String? {
        guard let progress, progress.total > 0 else { return nil }
        return L10n.string("%@/%@ done", "\(progress.done)", "\(progress.total)")
    }

    public var shortID: String {
        if id.count <= 10 {
            return id
        }
        return String(id.prefix(10))
    }

    public func matchesSearch(_ query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }

        let foldingOptions: String.CompareOptions = [.diacriticInsensitive, .caseInsensitive]
        let normalizedQuery = trimmedQuery.folding(options: foldingOptions, locale: Locale.current)
        var haystacks: [String] = [
            id,
            resolvedTitle,
            body ?? "",
            assignee ?? "",
            status.displayTitle,
            tenant ?? "",
            result ?? "",
            workspacePath ?? "",
            createdBy ?? "",
            warnings?.searchText ?? ""
        ]
        haystacks.append(contentsOf: skills)
        haystacks.append(contentsOf: parentIDs)
        haystacks.append(contentsOf: childIDs)

        return haystacks.contains { value in
            value.folding(options: foldingOptions, locale: Locale.current)
                .localizedStandardContains(normalizedQuery)
        }
    }

    private func trimmedText(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

public enum KanbanTaskStatus: Hashable, Codable, Sendable {
    case triage
    case todo
    case ready
    case running
    case blocked
    case done
    case archived
    case other(String)

    public static let boardStatuses: [KanbanTaskStatus] = [
        .triage,
        .todo,
        .ready,
        .running,
        .blocked,
        .done,
        .archived
    ]

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "triage":
            self = .triage
        case "todo":
            self = .todo
        case "ready":
            self = .ready
        case "running":
            self = .running
        case "blocked":
            self = .blocked
        case "done":
            self = .done
        case "archived":
            self = .archived
        default:
            self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .triage:
            "triage"
        case .todo:
            "todo"
        case .ready:
            "ready"
        case .running:
            "running"
        case .blocked:
            "blocked"
        case .done:
            "done"
        case .archived:
            "archived"
        case .other(let value):
            value
        }
    }

    public var displayTitle: String {
        switch self {
        case .triage:
            "Triage"
        case .todo:
            "Todo"
        case .ready:
            "Ready"
        case .running:
            "Running"
        case .blocked:
            "Blocked"
        case .done:
            "Done"
        case .archived:
            "Archived"
        case .other(let value):
            value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

public enum KanbanWorkspaceKind: Hashable, Codable, Sendable {
    case scratch
    case worktree
    case directory
    case other(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self = Self(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public init(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "scratch":
            self = .scratch
        case "worktree":
            self = .worktree
        case "dir":
            self = .directory
        default:
            self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .scratch:
            "scratch"
        case .worktree:
            "worktree"
        case .directory:
            "dir"
        case .other(let value):
            value
        }
    }

    public var displayTitle: String {
        switch self {
        case .scratch:
            "Scratch"
        case .worktree:
            "Worktree"
        case .directory:
            "Directory"
        case .other(let value):
            value.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

public struct KanbanTaskProgress: Codable, Hashable, Sendable {
    public let done: Int
    public let total: Int
}

public struct KanbanTaskWarnings: Codable, Hashable, Sendable {
    public let count: Int
    public let kinds: [String: Int]
    public let latestAt: Int?

    enum CodingKeys: String, CodingKey {
        case count
        case kinds
        case latestAt = "latest_at"
    }

    public init(count: Int, kinds: [String: Int], latestAt: Int?) {
        self.count = count
        self.kinds = kinds
        self.latestAt = latestAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 0
        kinds = try container.decodeIfPresent([String: Int].self, forKey: .kinds) ?? [:]
        latestAt = try container.decodeIfPresent(Int.self, forKey: .latestAt)
    }

    public var hasWarnings: Bool {
        count > 0 || !kinds.isEmpty
    }

    public var latestDate: Date? {
        latestAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    public var includesBlockedCompletion: Bool {
        (kinds["completion_blocked_hallucination"] ?? 0) > 0
    }

    public var includesSuspectedReferences: Bool {
        (kinds["suspected_hallucinated_references"] ?? 0) > 0
    }

    public var displayTitle: String {
        if includesBlockedCompletion && includesSuspectedReferences {
            return "Completion and reference warnings"
        }
        if includesBlockedCompletion {
            return "Completion blocked by phantom card claims"
        }
        if includesSuspectedReferences {
            return "Possible phantom task references"
        }
        return "Kanban recovery warning"
    }

    public var displayMessage: String {
        if includesBlockedCompletion {
            return "ARES Agent rejected a completion because the worker claimed cards that do not exist or were not created by that worker."
        }
        if includesSuspectedReferences {
            return "ARES Agent found task IDs in the completion text that do not resolve on the board."
        }
        return "ARES Agent recorded warning events that may need recovery."
    }

    public var searchText: String {
        ([displayTitle, displayMessage] + kinds.keys).joined(separator: " ")
    }
}

public struct KanbanTaskDetail: Codable, Hashable, Sendable {
    public let task: KanbanTask
    public let parentIDs: [String]
    public let childIDs: [String]
    public let comments: [KanbanComment]
    public let events: [KanbanEvent]
    public let runs: [KanbanRun]
    public let workerLog: String?
    public let homeChannels: [KanbanHomeChannel]

    enum CodingKeys: String, CodingKey {
        case task
        case parentIDs = "parent_ids"
        case childIDs = "child_ids"
        case comments
        case events
        case runs
        case workerLog = "worker_log"
        case homeChannels = "home_channels"
    }

    public init(
        task: KanbanTask,
        parentIDs: [String],
        childIDs: [String],
        comments: [KanbanComment],
        events: [KanbanEvent],
        runs: [KanbanRun],
        workerLog: String?,
        homeChannels: [KanbanHomeChannel] = []
    ) {
        self.task = task
        self.parentIDs = parentIDs
        self.childIDs = childIDs
        self.comments = comments
        self.events = events
        self.runs = runs
        self.workerLog = workerLog
        self.homeChannels = homeChannels
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        task = try container.decode(KanbanTask.self, forKey: .task)
        parentIDs = try container.decodeIfPresent([String].self, forKey: .parentIDs) ?? []
        childIDs = try container.decodeIfPresent([String].self, forKey: .childIDs) ?? []
        comments = try container.decodeIfPresent([KanbanComment].self, forKey: .comments) ?? []
        events = try container.decodeIfPresent([KanbanEvent].self, forKey: .events) ?? []
        runs = try container.decodeIfPresent([KanbanRun].self, forKey: .runs) ?? []
        workerLog = try container.decodeIfPresent(String.self, forKey: .workerLog)
        homeChannels = try container.decodeIfPresent([KanbanHomeChannel].self, forKey: .homeChannels) ?? []
    }
}

public struct KanbanHomeChannel: Codable, Identifiable, Hashable, Sendable {
    public let platform: String
    public let chatID: String
    public let threadID: String
    public let name: String?
    public let subscribed: Bool

    enum CodingKeys: String, CodingKey {
        case platform
        case chatID = "chat_id"
        case threadID = "thread_id"
        case name
        case subscribed
    }

    public init(
        platform: String,
        chatID: String,
        threadID: String = "",
        name: String? = nil,
        subscribed: Bool = false
    ) {
        self.platform = platform
        self.chatID = chatID
        self.threadID = threadID
        self.name = name
        self.subscribed = subscribed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        platform = try container.decode(String.self, forKey: .platform)
        chatID = try container.decode(String.self, forKey: .chatID)
        threadID = try container.decodeIfPresent(String.self, forKey: .threadID) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name)
        subscribed = try container.decodeIfPresent(Bool.self, forKey: .subscribed) ?? false
    }

    public var id: String {
        "\(platform):\(chatID):\(threadID)"
    }

    public var resolvedName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? L10n.string("Home") : trimmed
    }

    public var displayPlatform: String {
        platform
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    public var destinationLabel: String {
        threadID.isEmpty ? chatID : "\(chatID) / \(threadID)"
    }
}

public struct KanbanComment: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let taskID: String
    public let author: String
    public let body: String
    public let createdAt: Int

    enum CodingKeys: String, CodingKey {
        case id
        case taskID = "task_id"
        case author
        case body
        case createdAt = "created_at"
    }

    public var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt))
    }
}

public struct KanbanEvent: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let taskID: String
    public let kind: String
    public let payload: [String: JSONValue]?
    public let createdAt: Int
    public let runID: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case taskID = "task_id"
        case kind
        case payload
        case createdAt = "created_at"
        case runID = "run_id"
    }

    public var createdDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt))
    }

    public var displayPayload: String? {
        guard let payload, !payload.isEmpty else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(JSONValue.object(payload)),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
}

public struct KanbanRun: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let taskID: String
    public let profile: String?
    public let stepKey: String?
    public let status: String
    public let outcome: String?
    public let summary: String?
    public let error: String?
    public let metadata: [String: JSONValue]?
    public let workerPID: Int?
    public let startedAt: Int
    public let endedAt: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case taskID = "task_id"
        case profile
        case stepKey = "step_key"
        case status
        case outcome
        case summary
        case error
        case metadata
        case workerPID = "worker_pid"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }

    public var startedDate: Date {
        Date(timeIntervalSince1970: TimeInterval(startedAt))
    }

    public var endedDate: Date? {
        endedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    public var resolvedOutcome: String {
        outcome ?? (endedAt == nil ? "running" : status)
    }
}

public struct KanbanAssignee: Codable, Identifiable, Hashable, Sendable {
    public let name: String
    public let onDisk: Bool
    public let counts: [String: Int]

    enum CodingKeys: String, CodingKey {
        case name
        case onDisk = "on_disk"
        case counts
    }

    public var id: String { name }
}

public struct KanbanStats: Codable, Hashable, Sendable {
    public let byStatus: [String: Int]
    public let byAssignee: [String: [String: Int]]
    public let oldestReadyAgeSeconds: Int?
    public let now: Int?

    enum CodingKeys: String, CodingKey {
        case byStatus = "by_status"
        case byAssignee = "by_assignee"
        case oldestReadyAgeSeconds = "oldest_ready_age_seconds"
        case now
    }
}

public struct KanbanDispatcherStatus: Codable, Hashable, Sendable {
    public let running: Bool?
    public let message: String?

    public var isKnownInactive: Bool {
        running == false
    }
}

public struct KanbanDispatchResult: Codable, Hashable, Sendable {
    public let reclaimed: Int
    public let crashed: [String]
    public let timedOut: [String]
    public let autoBlocked: [String]
    public let promoted: Int
    public let spawned: [KanbanSpawnedTask]
    public let skippedUnassigned: [String]

    enum CodingKeys: String, CodingKey {
        case reclaimed
        case crashed
        case timedOut = "timed_out"
        case autoBlocked = "auto_blocked"
        case promoted
        case spawned
        case skippedUnassigned = "skipped_unassigned"
    }
}

public struct KanbanSpawnedTask: Codable, Hashable, Sendable {
    public let taskID: String
    public let assignee: String
    public let workspace: String

    enum CodingKeys: String, CodingKey {
        case taskID = "task_id"
        case assignee
        case workspace
    }
}

public struct KanbanTaskDraft: Equatable, Hashable, Sendable {
    public init() {}
    public var title = ""
    public var body = ""
    public var assignee = ""
    public var priority = 0
    public var maxRetriesText = ""
    public var tenant = ""
    public var skillsText = ""
    public var parentIDsText = ""
    public var startsInTriage = false

    public var normalizedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var normalizedBody: String? {
        let value = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public var normalizedAssignee: String? {
        let value = assignee.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public var normalizedTenant: String? {
        let value = tenant.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public var normalizedMaxRetries: Int? {
        let value = maxRetriesText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        return Int(value)
    }

    public var skills: [String] {
        Self.normalizedCommaList(skillsText)
    }

    public var parentIDs: [String] {
        Self.normalizedIDList(parentIDsText)
    }

    public var validationError: String? {
        if normalizedTitle.isEmpty {
            return "Task title is required."
        }
        let trimmedMaxRetries = maxRetriesText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMaxRetries.isEmpty {
            guard let maxRetries = Int(trimmedMaxRetries), maxRetries > 0 else {
                return "Max retries must be a whole number greater than 0."
            }
        }
        return nil
    }

    public static func normalizedCommaList(_ value: String) -> [String] {
        uniquePreservingOrder(
            value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    public static func normalizedIDList(_ value: String) -> [String] {
        let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))
        return uniquePreservingOrder(
            value
                .components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    public static func listText(_ values: [String]) -> String {
        values.joined(separator: ", ")
    }

    private static func uniquePreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }
}

public struct KanbanBoardDraft: Equatable, Hashable, Sendable {
    public init() {}
    public var slug = ""
    public var name = ""
    public var description = ""
    public var icon = ""
    public var color = ""
    public var switchAfterCreate = false

    public var normalizedSlug: String {
        slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public var normalizedName: String? {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public var normalizedDescription: String? {
        let value = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public var normalizedIcon: String? {
        let value = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public var normalizedColor: String? {
        let value = color.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public var validationError: String? {
        if normalizedSlug.isEmpty {
            return "Board slug is required."
        }
        if normalizedSlug.range(of: #"^[a-z0-9][a-z0-9\-_]{0,63}$"#, options: .regularExpression) == nil {
            return "Board slug must be 1-64 lowercase letters, numbers, hyphens, or underscores."
        }
        return nil
    }
}

public struct KanbanActionDraft: Equatable {
    public init() {}
    public init(comment: String = "", result: String = "", blockReason: String = "", recoveryReason: String = "", recoverySummary: String = "", recoveryMetadata: String = "", reclaimBeforeReassign: Bool = false, assignee: String = "", body: String = "", tenant: String = "", priority: Int = 0, skillsText: String = "", parentIDsText: String = "", childIDsText: String = "") {
        self.comment = comment; self.result = result; self.blockReason = blockReason; self.recoveryReason = recoveryReason; self.recoverySummary = recoverySummary; self.recoveryMetadata = recoveryMetadata; self.reclaimBeforeReassign = reclaimBeforeReassign; self.assignee = assignee; self.body = body; self.tenant = tenant; self.priority = priority; self.skillsText = skillsText; self.parentIDsText = parentIDsText; self.childIDsText = childIDsText
    }
    public var comment = ""
    public var result = ""
    public var blockReason = ""
    public var recoveryReason = ""
    public var recoverySummary = ""
    public var recoveryMetadata = ""
    public var reclaimBeforeReassign = false
    public var assignee = ""
    public var body = ""
    public var tenant = ""
    public var priority = 0
    public var skillsText = ""
    public var parentIDsText = ""
    public var childIDsText = ""

    public var normalizedComment: String? {
        let value = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public var normalizedResult: String? {
        let value = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public var normalizedBlockReason: String? {
        let value = blockReason.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public var normalizedRecoveryReason: String? {
        let value = recoveryReason.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public var normalizedRecoverySummary: String? {
        let value = recoverySummary.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public var normalizedRecoveryMetadata: String? {
        let value = recoveryMetadata.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public var normalizedAssignee: String? {
        let value = assignee.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    public var normalizedBodyForUpdate: String {
        body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var normalizedTenantForUpdate: String {
        tenant.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var skills: [String] {
        KanbanTaskDraft.normalizedCommaList(skillsText)
    }

    public var parentIDs: [String] {
        KanbanTaskDraft.normalizedIDList(parentIDsText)
    }

    public var childIDs: [String] {
        KanbanTaskDraft.normalizedIDList(childIDsText)
    }
}