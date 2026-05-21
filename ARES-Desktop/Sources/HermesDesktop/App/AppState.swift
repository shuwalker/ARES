import Combine
import Foundation
import SwiftUI

enum PendingSectionEntryAction {
    case openNewConnectionEditor
    case prepareNewSessionComposer
    case openNewTerminalTab(ConnectionProfile)
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedSection: AppSection = .connections
    @Published var activeAlert: AppAlert?
    @Published var isBusy = false
    @Published var statusMessage: String?
    @Published var overview: RemoteDiscovery?
    @Published var overviewError: String?
    @Published var isRefreshingOverview = false
    @Published var activeConnectionID: UUID?
    @Published var selectedSessionID: String?
    @Published var sessions: [SessionSummary] = []
    @Published var sessionMessages: [SessionMessage] = []
    @Published var sessionMessageDisplays: [SessionMessageDisplay] = []
    @Published var sessionsError: String?
    @Published var isLoadingSessions = false
    @Published var isRefreshingSessions = false
    @Published var isDeletingSession = false
    @Published var isSendingSessionMessage = false
    @Published var sessionConversationError: String?
    @Published var pendingSessionTurn: PendingSessionTurn?
    // Streaming chat state
    @Published var chatMessages: [ChatMessage] = []
    @Published var isStreamingChat = false
    @Published var chatError: String?
    @Published var chatSessionID: String?
    @Published var thinkingLevel: ThinkingLevel = .off
    @Published var hasMoreSessions = false
    @Published var totalSessionsCount = 0
    @Published var sessionSearchQuery = ""
    @Published var sessionPinStateVersion = 0
    @Published var selectedWorkflowID: UUID?
    @Published var workflows: [WorkflowPreset] = []
    @Published var usageSummary: UsageSummary?
    @Published var usageProfileBreakdown: UsageProfileBreakdown?
    @Published var usageError: String?
    @Published var isLoadingUsage = false
    @Published var isRefreshingUsage = false
    @Published var analyticsResponse: AnalyticsResponse?
    @Published var modelsAnalyticsResponse: ModelsAnalyticsResponse?
    @Published var isLoadingAnalytics = false
    @Published var isRefreshingAnalytics = false
    @Published var analyticsError: String?
    @Published var analyticsDays: Int = 30
    @Published var selectedSkillID: String?
    @Published var skills: [SkillSummary] = []
    @Published var selectedSkillDetail: SkillDetail?
    @Published var skillsError: String?
    @Published var isLoadingSkills = false
    @Published var isRefreshingSkills = false
    @Published var isLoadingSkillDetail = false
    @Published var isSavingSkillDraft = false
    @Published var cronJobs: [CronJob] = []
    @Published var selectedCronJobID: String?
    @Published var cronJobsError: String?
    @Published var isLoadingCronJobs = false
    @Published var isRefreshingCronJobs = false
    @Published var isOperatingOnCronJob = false
    @Published var operatingCronJobID: String?
    @Published var isSavingCronJobDraft = false
    @Published var kanbanBoards: [KanbanProject] = []
    @Published var selectedKanbanBoardSlug = KanbanProject.defaultSlug
    @Published var remoteCurrentKanbanBoardSlug: String?
    @Published var supportsKanbanBoardManagement = false
    @Published var kanbanBoard: KanbanBoard?
    @Published var selectedKanbanTaskID: String?
    @Published var selectedKanbanTaskDetail: KanbanTaskDetail?
    @Published var kanbanError: String?
    @Published var isLoadingKanbanBoards = false
    @Published var isLoadingKanbanBoard = false
    @Published var isRefreshingKanbanBoard = false
    @Published var isLoadingKanbanTaskDetail = false
    @Published var isOperatingOnKanbanTask = false
    @Published var operatingKanbanTaskID: String?
    @Published var isSavingKanbanTaskDraft = false
    @Published var isSavingKanbanBoardDraft = false
    @Published var isOperatingOnKanbanBoard = false
    @Published var isDispatchingKanban = false
    @Published var includeArchivedKanbanTasks = false
    @Published var kanbanTaskLog: String? = nil
    @Published var isLoadingKanbanLog = false
    @Published var kanbanOrchestration: KanbanOrchestrationConfig? = nil
    @Published var isLoadingKanbanOrchestration = false
    @Published var kanbanOrchestrationError: String? = nil
    @Published var kanbanSelectedTaskIDs: Set<String> = []
    @Published var secondBrainResults: [SecondBrainResult] = []
    @Published var selectedSecondBrainResultID: String?
    @Published var secondBrainError: String?
    @Published var isLoadingSecondBrain = false
    @Published var isRefreshingSecondBrain = false
    @Published var youtubeVideos: [YouTubeVideoEntry] = []
    @Published var selectedYouTubeVideoID: String?
    @Published var youtubeError: String?
    @Published var isLoadingYouTube = false
    @Published var isRefreshingYouTube = false
    @Published var isOperatingOnYouTube = false
    @Published var selectedWorkspaceFileID: String = RemoteTrackedFile.memory.workspaceFileID
    @Published var workspaceFileDocuments: [String: FileEditorDocument] = [:]
    @Published var workspaceFileBrowserListing: RemoteDirectoryListing?
    @Published var workspaceFileBrowserError: String?
    @Published var isLoadingWorkspaceFileBrowser = false
    /// Set to the fileID when a save is rejected because the remote file changed since load.
    /// The UI observes this to show a "Overwrite anyway?" conflict alert.
    @Published var workspaceFileSaveConflictFileID: String?
    @Published var pendingSectionSelection: AppSection?
    @Published var showDiscardChangesAlert = false
    @Published var pendingNewConnectionEditorRequestID: UUID?
    @Published var searchFocusRequestID: UUID?
    @Published var availableUpdate: AvailableUpdate?
    @Published var isCheckingForUpdates = false
    @Published var isDesktopPetMode = false
    @Published var isSearchVisible = false
    /// A prompt string set by WorkflowPresetsView to pre-populate the chat input when switching to the chat section.
    @Published var pendingChatInput: String? = nil

    // MARK: - Soul
    @Published var soulContent: String?
    @Published var isSavingSoul = false
    @Published var soulError: String?

    // MARK: - Memory
    @Published var memoryEntries: [MemoryEntry] = []
    @Published var isLoadingMemory = false
    @Published var memoryError: String?

    // MARK: - Tools
    @Published var tools: [ToolSummary] = []
    @Published var isLoadingTools = false
    @Published var toolsError: String?

    // MARK: - Tool Approvals
    @Published var pendingApprovals: [ToolApprovalRequest] = []

    // MARK: - Jobs (Dashboard Cron Jobs)
    @Published var dashboardCronJobs: [DashboardCronJob] = []
    @Published var isLoadingDashboardCronJobs = false
    @Published var dashboardCronJobsError: String?

    // MARK: - MCP Servers
    @Published var mcpServers: [MCPServer] = []
    @Published var mcpMarketplaceItems: [MCPMarketplaceItem] = []
    @Published var isLoadingMCP = false
    @Published var mcpError: String?

    // MARK: - Swarm
    @Published var swarmWorkers: [SwarmWorker] = []
    @Published var swarmMissions: [SwarmMission] = []
    @Published var swarmHealth: SwarmHealth?
    @Published var swarmKanbanCards: [SwarmKanbanCard] = []
    @Published var swarmReports: [SwarmReport] = []
    @Published var swarmMemoryFiles: [SwarmMemoryFile] = []
    @Published var isLoadingSwarm = false
    @Published var swarmError: String?
    @Published var swarmSelectedWorker: SwarmWorker?
    @Published var swarmRuntimeOutput: [String: String] = [:]   // workerId -> terminal text
    var swarmPollingTask: Task<Void, Never>?
    var swarmRuntimePollingTask: Task<Void, Never>?

    // MARK: - Conductor
    @Published var conductorGoal: String = ""
    @Published var conductorMissionActive: Bool = false
    @Published var conductorWorkerCards: [ConductorWorkerCard] = []
    @Published var conductorSelectedModel: String = ""
    @Published var conductorError: String?
    var conductorPollingTask: Task<Void, Never>?

    // MARK: - Operations
    @Published var operationsAgents: [OperationsAgent] = []
    @Published var isLoadingOperations = false
    @Published var operationsError: String?

    // MARK: - Crew Status
    @Published var crewStatusEntries: [CrewStatusEntry] = []
    @Published var isLoadingCrewStatus = false
    @Published var crewStatusError: String?
    var crewStatusPollingTask: Task<Void, Never>?

    // MARK: - Dashboard Analytics (Feature 1)
    @Published var dashboardOverview: DashboardOverview?
    @Published var isLoadingDashboard = false
    @Published var dashboardPeriod: Int = 14

    // MARK: - Usage Meter / Session Context (Feature 2)
    @Published var sessionContextUsed: Int = 0
    @Published var sessionContextLimit: Int = 200_000
    @Published var sessionDailyCost: Double = 0
    @Published var contextAlertThreshold: Int? = nil

    /// Lightweight observable update-check helper. Distinct from `updateCheckService`,
    /// which is injected via `init` for testability. `updateChecker` uses default
    /// configuration and is suitable for direct use from SwiftUI views.
    let updateChecker = UpdateCheckService()

    let connectionStore: ConnectionStore
    let dashboardAPIService: DashboardAPIService
    let tunnelService = SSHTunnelService()
    let sshTransport: SSHTransport
    let httpTransport: HTTPTransport
    let webSocketTransport: WebSocketTransport
    let remoteHermesService: RemoteHermesService
    let fileEditorService: FileEditorService
    let sessionBrowserService: SessionBrowserService
    let hermesChatService: HermesChatService
    let usageBrowserService: UsageBrowserService
    let skillBrowserService: SkillBrowserService
    let cronBrowserService: CronBrowserService
    let kanbanBrowserService: KanbanBrowserService
    let secondBrainService: SecondBrainService
    let youtubePipelineService: YouTubePipelineService
    let soulService: SoulService
    let updateCheckService: UpdateCheckService
    let terminalWorkspace: TerminalWorkspaceStore
    let workflowLaunchDiagnostics: WorkflowLaunchDiagnostics

    let sessionPageSize = 50

    /// Returns the appropriate transport for the given connection profile.
    /// Local connections use HTTPTransport; SSH connections use SSHTransport.
    func transport(for connection: ConnectionProfile) -> any HermesTransport {
        switch connection.transportKind {
        case .local:
            return httpTransport
        case .ssh:
            return sshTransport
        }
    }
    let approvalNeededMessage = "Hermes requested command approval, but this chat turn cannot collect manual approvals. Retry this turn with Auto-approve enabled, or resume the session in Terminal to review the command yourself."
    var sessionOffset = 0
    var pendingSessionReloadQuery: String?
    var pendingSectionEntryAction: PendingSectionEntryAction?
    var isNewSessionComposerActive = false
    var sessionScrollOffsets: [String: CGFloat] = [:]
    var sessionMessageSignature = SessionMessageSignature(messages: [])
    var connectionTestRequestID: UUID?
    var hasPerformedAutomaticUpdateCheck = false
    let automaticUpdateCheckInterval: TimeInterval = 24 * 60 * 60
    var statusTask: Task<Void, Never>?
    var sessionTranscriptPollingTask: Task<Void, Never>?
    var approvalPollingTask: Task<Void, Never>?
    var contextPollingTask: Task<Void, Never>?
    var firedContextThresholds: Set<Int> = []
    private var cancellables = Set<AnyCancellable>()

    convenience init(updateCheckService: UpdateCheckService = UpdateCheckService()) {
        self.init(paths: AppPaths(), updateCheckService: updateCheckService)
    }

    init(paths: AppPaths, updateCheckService: UpdateCheckService = UpdateCheckService()) {
        let connectionStore = ConnectionStore(paths: paths)
        let sshTransport = SSHTransport(paths: paths)
        let workflowLaunchLogURL = paths.applicationSupportURL
            .appendingPathComponent("Diagnostics", isDirectory: true)
            .appendingPathComponent("workflow-launch-latest.log")
        let workflowLaunchDiagnostics = WorkflowLaunchDiagnostics(logFileURL: workflowLaunchLogURL)

        self.connectionStore = connectionStore
        self.sshTransport = sshTransport
        self.httpTransport = HTTPTransport()
        self.webSocketTransport = WebSocketTransport()
        self.remoteHermesService = RemoteHermesService(sshTransport: sshTransport)
        self.fileEditorService = FileEditorService(sshTransport: sshTransport)
        self.sessionBrowserService = SessionBrowserService(sshTransport: sshTransport)
        self.hermesChatService = HermesChatService(sshTransport: sshTransport)
        self.usageBrowserService = UsageBrowserService(sshTransport: sshTransport)
        self.skillBrowserService = SkillBrowserService(sshTransport: sshTransport)
        self.cronBrowserService = CronBrowserService(sshTransport: sshTransport)
        self.kanbanBrowserService = KanbanBrowserService(sshTransport: sshTransport)
        self.secondBrainService = SecondBrainService(sshTransport: sshTransport)
        self.youtubePipelineService = YouTubePipelineService(sshTransport: sshTransport)
        self.soulService = SoulService(sshTransport: sshTransport)
        self.updateCheckService = updateCheckService
        self.workflowLaunchDiagnostics = workflowLaunchDiagnostics

        // Wire up the dashboard API service
        let dashboardBaseURL = URL(string: "http://localhost:9119")!
        self.dashboardAPIService = DashboardAPIService(
            httpTransport: httpTransport,
            baseURL: dashboardBaseURL
        )
        self.terminalWorkspace = TerminalWorkspaceStore(
            sshTransport: sshTransport,
            workflowLaunchDiagnostics: workflowLaunchDiagnostics
        )

        connectionStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.objectWillChange.send()
                    guard let active = self.activeConnection else { return }
                    // If an SSH tunnel is active, keep using the tunneled URL.
                    // Read localPort once to avoid TOCTOU race.
                    let tunnelPort = self.tunnelService.localPort
                    if let tunnelPort {
                        self.dashboardAPIService.baseURL = active.tunneledDashboardURL(localPort: tunnelPort)
                    } else {
                        self.dashboardAPIService.baseURL = active.dashboardURL
                    }
                }
            }
            .store(in: &cancellables)

        connectionStore.$persistenceError
            .compactMap { $0 }
            .sink { [weak self] message in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.activeAlert = AppAlert(
                        title: L10n.string("Local storage error"),
                        message: message
                    )
                    self.setStatusMessage(L10n.string("Local storage error"))
                }
            }
            .store(in: &cancellables)

        self.activeConnectionID = connectionStore.lastConnectionID

        if let lastID = activeConnectionID,
           let profile = connectionStore.connections.first(where: { $0.id == lastID }) {
            // Auto-reconnect the tunnel / direct HTTP on launch without switching sections
            Task {
                await startTunnelIfNeeded(for: profile)
            }
        }

        if activeConnectionID != nil {
            selectedSection = .overview
        }
    }

    // MARK: - Core computed properties

    var activeConnection: ConnectionProfile? {
        guard let activeConnectionID else { return nil }
        return connectionStore.connections.first(where: { $0.id == activeConnectionID })
    }

    /// True when the dashboard API is reachable — either the connection is local,
    /// direct HTTP (LAN) transport is configured, or an SSH tunnel has been established.
    var dashboardAPIAvailable: Bool {
        guard let connection = activeConnection else { return false }
        if connection.transportMode == .directHTTP { return true }
        return connection.transportKind == .local || tunnelService.localPort != nil
    }

    var selectedKanbanBoard: KanbanProject? {
        kanbanBoards.first(where: { $0.slug == selectedKanbanBoardSlug })
    }

    var canonicalWorkspaceFileReferences: [WorkspaceFileReference] {
        guard let activeConnection else { return [] }

        return RemoteTrackedFile.allCases.map { trackedFile in
            WorkspaceFileReference.canonical(
                trackedFile,
                remotePath: resolvedRemotePath(for: trackedFile, connection: activeConnection)
            )
        }
    }

    var bookmarkedWorkspaceFileReferences: [WorkspaceFileReference] {
        guard let activeConnection else { return [] }

        return connectionStore
            .bookmarks(for: activeConnection.workspaceScopeFingerprint)
            .map(WorkspaceFileReference.bookmark)
    }

    var bookmarkedWorkspaceFileGroups: [WorkspaceFileBookmarkGroup] {
        WorkspaceFileBookmarkGroup.groups(for: bookmarkedWorkspaceFileReferences)
    }

    var workspaceFileReferences: [WorkspaceFileReference] {
        canonicalWorkspaceFileReferences + bookmarkedWorkspaceFileReferences
    }

    var pinnedSessionSummaries: [SessionSummary] {
        guard let activeConnection else { return [] }

        return connectionStore
            .pinnedSessions(for: activeConnection.workspaceScopeFingerprint)
            .map { pinnedSession in
                sessions.first(where: { $0.id == pinnedSession.id }) ?? pinnedSession.summary
            }
    }

    var unpinnedSessions: [SessionSummary] {
        guard let activeConnection else { return sessions }
        let pinnedIDs = Set(
            connectionStore
                .pinnedSessions(for: activeConnection.workspaceScopeFingerprint)
                .map(\.id)
        )
        return sessions.filter { !pinnedIDs.contains($0.id) }
    }

    var selectedWorkspaceFileReference: WorkspaceFileReference? {
        workspaceFileReferences.first { $0.id == selectedWorkspaceFileID } ??
            workspaceFileReferences.first
    }

    var workspaceFileBrowserDefaultPath: String {
        overview?.hermesHome ?? activeConnection?.remoteHermesHomePath ?? "~"
    }

    var hasUnsavedFileChanges: Bool {
        workspaceFileDocuments.values.contains { $0.isDirty }
    }

    var canRefreshCurrentSection: Bool {
        guard activeConnection != nil else { return false }

        switch selectedSection {
        case .overview:
            return !isRefreshingOverview && !isBusy
        case .sessions:
            return !isLoadingSessions && !isRefreshingSessions
        case .workflows:
            return !isLoadingSkills && !isRefreshingSkills
        case .cronjobs:
            return !isLoadingCronJobs && !isRefreshingCronJobs
        case .kanban:
            return !isLoadingKanbanBoards && !isLoadingKanbanBoard && !isRefreshingKanbanBoard
        case .secondBrain:
            return !isLoadingSecondBrain && !isRefreshingSecondBrain
        case .youtubePipeline:
            return !isLoadingYouTube && !isRefreshingYouTube && !isOperatingOnYouTube
        case .usage:
            return !isLoadingUsage && !isRefreshingUsage && !isLoadingAnalytics && !isRefreshingAnalytics
        case .analytics:
            return !isLoadingDashboard
        case .skills:
            return !isLoadingSkills && !isRefreshingSkills
        case .jobs:
            return !isLoadingDashboardCronJobs
        case .mcp:
            return !isLoadingMCP
        case .swarm:
            return !isLoadingSwarm
        case .conductor:
            return !conductorMissionActive
        case .operations:
            return !isLoadingOperations
        case .crewStatus:
            return !isLoadingCrewStatus
        case .connections, .files, .terminal, .avatar, .physicsSim, .models, .config, .logs, .keys, .profiles, .plugins, .docs, .chat, .memory, .soul, .tools, .office:
            return false
        }
    }

    var canSaveCurrentWorkspaceFile: Bool {
        guard selectedSection == .files else { return false }
        guard let document = workspaceFileDocuments[selectedWorkspaceFileID] else { return false }
        return document.hasLoaded && document.isDirty && !document.isLoading
    }

    var canFocusSearchCurrentSection: Bool {
        guard activeConnection != nil else { return false }

        switch selectedSection {
        case .sessions, .workflows, .cronjobs, .kanban, .skills, .youtubePipeline, .models, .config, .logs, .keys, .profiles, .plugins:
            return true
        case .jobs, .mcp, .analytics, .swarm, .conductor, .operations, .crewStatus:
            return false
        case .connections, .overview, .files, .usage, .terminal, .avatar, .secondBrain, .physicsSim, .docs, .chat, .memory, .soul, .tools, .office:
            return false
        }
    }

    func isSectionAvailable(_ section: AppSection) -> Bool {
        section == .connections || activeConnection != nil
    }

    // MARK: - Private helpers used across multiple extension files

    private func resolvedRemotePath(for trackedFile: RemoteTrackedFile, connection: ConnectionProfile) -> String {
        trackedFile.resolvedRemotePath(using: overview?.paths) ?? connection.remotePath(for: trackedFile)
    }
}

// MARK: - Private supporting types

struct SessionMessageSignature: Equatable, Sendable {
    let count: Int
    let digest: Int

    init(messages: [SessionMessage]) {
        var hasher = Hasher()
        hasher.combine(messages.count)

        for message in messages {
            hasher.combine(message.id)
            hasher.combine(message.role)
            hasher.combine(message.content)
            hasher.combine(message.timestamp)
            hasher.combine(message.metadata)
        }

        count = messages.count
        digest = hasher.finalize()
    }
}

struct ConnectionTestRequest: Encodable {}

struct ConnectionTestResponse: Decodable {
    let ok: Bool
    let remoteHome: String
    let pythonExecutable: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case remoteHome = "remote_home"
        case pythonExecutable = "python_executable"
    }
}
