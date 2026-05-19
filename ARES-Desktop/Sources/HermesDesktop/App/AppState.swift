import Combine
import Foundation
import SwiftUI

private enum PendingSectionEntryAction {
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
    @Published private(set) var sessionSearchQuery = ""
    @Published private(set) var sessionPinStateVersion = 0
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
    @Published var pendingSectionSelection: AppSection?
    @Published var showDiscardChangesAlert = false
    @Published var pendingNewConnectionEditorRequestID: UUID?
    @Published var searchFocusRequestID: UUID?
    @Published var availableUpdate: AvailableUpdate?
    @Published var isCheckingForUpdates = false
    @Published var isDesktopPetMode = false
    @Published var isSearchVisible = false

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

    // MARK: - Dashboard Analytics (Feature 1)
    @Published var dashboardOverview: DashboardOverview?
    @Published var isLoadingDashboard = false
    @Published var dashboardPeriod: Int = 14

    // MARK: - Usage Meter / Session Context (Feature 2)
    @Published var sessionContextUsed: Int = 0
    @Published var sessionContextLimit: Int = 200_000
    @Published var sessionDailyCost: Double = 0
    @Published var contextAlertThreshold: Int? = nil

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

    private let sessionPageSize = 50

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
    private let approvalNeededMessage = "Hermes requested command approval, but this chat turn cannot collect manual approvals. Retry this turn with Auto-approve enabled, or resume the session in Terminal to review the command yourself."
    private var sessionOffset = 0
    private var pendingSessionReloadQuery: String?
    private var pendingSectionEntryAction: PendingSectionEntryAction?
    private var isNewSessionComposerActive = false
    private var sessionScrollOffsets: [String: CGFloat] = [:]
    private var sessionMessageSignature = SessionMessageSignature(messages: [])
    private var connectionTestRequestID: UUID?
    private var hasPerformedAutomaticUpdateCheck = false
    private let automaticUpdateCheckInterval: TimeInterval = 24 * 60 * 60
    private var statusTask: Task<Void, Never>?
    private var sessionTranscriptPollingTask: Task<Void, Never>?
    private var approvalPollingTask: Task<Void, Never>?
    private var contextPollingTask: Task<Void, Never>?
    private var firedContextThresholds: Set<Int> = []
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
                self?.objectWillChange.send()
                if let self, let active = self.activeConnection {
                    // If an SSH tunnel is active, keep using the tunneled URL.
                    if let tunnelPort = self.tunnelService.localPort {
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
                self?.activeAlert = AppAlert(
                    title: L10n.string("Local storage error"),
                    message: message
                )
                self?.setStatusMessage(L10n.string("Local storage error"))
            }
            .store(in: &cancellables)

        self.activeConnectionID = connectionStore.lastConnectionID

        if activeConnectionID != nil {
            selectedSection = .overview
        }
    }

    var activeConnection: ConnectionProfile? {
        guard let activeConnectionID else { return nil }
        return connectionStore.connections.first(where: { $0.id == activeConnectionID })
    }

    /// True when the dashboard API is reachable — either the connection is local,
    /// or an SSH tunnel has been established and its local port is known.
    var dashboardAPIAvailable: Bool {
        guard let connection = activeConnection else { return false }
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
        case .jobs, .mcp, .analytics:
            return false
        case .connections, .overview, .files, .usage, .terminal, .avatar, .secondBrain, .physicsSim, .docs, .chat, .memory, .soul, .tools, .office:
            return false
        }
    }

    func isSectionAvailable(_ section: AppSection) -> Bool {
        section == .connections || activeConnection != nil
    }

    func requestSectionSelection(_ section: AppSection) {
        guard selectedSection != section else { return }
        guard section != .files || activeConnection != nil else {
            selectedSection = .connections
            return
        }

        if hasUnsavedFileChanges && selectedSection == .files {
            pendingSectionSelection = section
            showDiscardChangesAlert = true
            return
        }

        selectedSection = section
        handleSectionEntry(section)
    }

    func requestNewConnectionEditorFromCommand() {
        pendingSectionEntryAction = .openNewConnectionEditor
        requestSectionSelection(.connections)
        guard selectedSection == .connections else { return }
        pendingNewConnectionEditorRequestID = UUID()
        pendingSectionEntryAction = nil
    }

    func consumeNewConnectionEditorRequest(_ requestID: UUID) {
        guard pendingNewConnectionEditorRequestID == requestID else { return }
        pendingNewConnectionEditorRequestID = nil
    }

    func requestNewSessionFromCommand() {
        guard activeConnection != nil, !isSendingSessionMessage else { return }
        pendingSectionEntryAction = .prepareNewSessionComposer
        isNewSessionComposerActive = true
        requestSectionSelection(.sessions)
        guard selectedSection == .sessions else { return }
        prepareNewSessionComposer()
        pendingSectionEntryAction = nil
    }

    func openNewTerminalTabFromCommand() {
        guard let profile = activeConnection else { return }
        let updatedProfile = profile.updated()

        if hasUnsavedFileChanges && selectedSection == .files {
            pendingSectionEntryAction = .openNewTerminalTab(updatedProfile)
            requestSectionSelection(.terminal)
            return
        }

        openNewTerminalTab(for: updatedProfile)
    }

    func requestSearchFocusFromCommand() {
        guard canFocusSearchCurrentSection else { return }
        searchFocusRequestID = UUID()
    }

    func refreshCurrentSectionFromCommand() async {
        guard canRefreshCurrentSection else { return }

        switch selectedSection {
        case .overview:
            await refreshOverview(manual: true)
        case .sessions:
            await refreshSessions(query: sessionSearchQuery)
        case .workflows:
            await refreshWorkflows()
        case .cronjobs:
            await refreshCronJobs()
        case .kanban:
            await refreshKanbanBoard()
        case .usage:
            await refreshUsage()
            await refreshAnalytics()
        case .skills:
            await refreshSkills()
        case .jobs:
            await loadDashboardCronJobs()
        case .mcp:
            await loadMCPServers()
        case .analytics:
            await loadDashboardOverview()
        case .secondBrain, .youtubePipeline, .physicsSim, .docs, .chat, .memory, .soul, .tools, .office:
            break
        case .connections, .files, .terminal, .avatar, .models, .config, .logs, .keys, .profiles, .plugins:
            break
        }
    }

    func checkForUpdatesAtLaunch() async {
        guard connectionStore.automaticallyChecksForUpdates else { return }
        guard !hasPerformedAutomaticUpdateCheck else { return }
        guard shouldRunAutomaticUpdateCheck() else { return }
        hasPerformedAutomaticUpdateCheck = true
        let didCompleteCheck = await checkForUpdates(presentsCurrentResult: false)
        if didCompleteCheck {
            connectionStore.lastAutomaticUpdateCheckAt = Date()
        }
    }

    func checkForUpdatesFromCommand() async {
        _ = await checkForUpdates(presentsCurrentResult: true)
    }

    func dismissAvailableUpdate() {
        availableUpdate = nil
    }

    func noteOpenedRelease(for update: AvailableUpdate) {
        dismissAvailableUpdate()
        setStatusMessage(L10n.string("Opening ARES %@ release…", update.latestVersion))
    }

    func updateAutomaticUpdateChecks(_ enabled: Bool) {
        connectionStore.automaticallyChecksForUpdates = enabled
    }

    func discardChangesAndContinue() {
        for fileID in Array(workspaceFileDocuments.keys) {
            var document = workspaceFileDocuments[fileID]
            document?.discardChanges()
            workspaceFileDocuments[fileID] = document
        }
        if let pendingSectionSelection {
            switch pendingSectionEntryAction {
            case .openNewConnectionEditor where pendingSectionSelection == .connections:
                pendingNewConnectionEditorRequestID = UUID()
                selectedSection = pendingSectionSelection
                handleSectionEntry(pendingSectionSelection)
            case .prepareNewSessionComposer where pendingSectionSelection == .sessions:
                selectedSection = pendingSectionSelection
                prepareNewSessionComposer()
                handleSectionEntry(pendingSectionSelection)
            case .openNewTerminalTab(let profile) where pendingSectionSelection == .terminal:
                openNewTerminalTab(for: profile)
            default:
                selectedSection = pendingSectionSelection
                handleSectionEntry(pendingSectionSelection)
            }
        }
        pendingSectionSelection = nil
        pendingSectionEntryAction = nil
    }

    func stayOnCurrentSection() {
        pendingSectionSelection = nil
        pendingSectionEntryAction = nil
        isNewSessionComposerActive = false
    }

    func connect(to profile: ConnectionProfile) {
        let isSwitchingConnection = activeConnection?.workspaceScopeFingerprint != profile.workspaceScopeFingerprint

        if isSwitchingConnection {
            resetWorkspaceStateForConnectionChange()
        }

        activeConnectionID = profile.id
        connectionStore.lastConnectionID = profile.id
        var updatedProfile = profile
        updatedProfile.lastConnectedAt = Date()
        connectionStore.upsert(updatedProfile)
        selectedSection = .overview
        setStatusMessage(L10n.string("Connecting to %@…", profile.label))

        Task {
            await startTunnelIfNeeded(for: profile)
            await prepareWorkspaceForActiveConnection()
        }
    }

    private func startTunnelIfNeeded(for profile: ConnectionProfile) async {
        guard profile.transportKind == .ssh else {
            tunnelService.stop()
            dashboardAPIService.baseURL = profile.dashboardURL
            return
        }

        do {
            try await tunnelService.start(connection: profile)
            if let port = tunnelService.localPort {
                dashboardAPIService.baseURL = profile.tunneledDashboardURL(localPort: port)
            } else {
                // Fallback: tunnel started but port not captured — use direct URL.
                dashboardAPIService.baseURL = profile.dashboardURL
            }
        } catch {
            // Tunnel failed — fall back to direct dashboard URL (will only work if not firewalled).
            dashboardAPIService.baseURL = profile.dashboardURL
        }
    }

    func saveConnection(_ profile: ConnectionProfile) {
        let normalized = profile.updated()
        let previous = connectionStore.connections.first(where: { $0.id == normalized.id })
        let isActiveConnection = activeConnectionID == normalized.id
        let isChangingWorkspaceScope = previous?.workspaceScopeFingerprint != normalized.workspaceScopeFingerprint

        if isActiveConnection && isChangingWorkspaceScope && hasUnsavedFileChanges {
            activeAlert = AppAlert(
                title: L10n.string("Unsaved file edits"),
                message: L10n.string("Save or discard Workspace Files edits before switching the Hermes profile for the active host.")
            )
            return
        }

        connectionStore.upsert(normalized)

        guard isActiveConnection else { return }
        guard isChangingWorkspaceScope else { return }

        resetWorkspaceStateForConnectionChange()
        selectedSection = .overview
        setStatusMessage(L10n.string("Refreshing %@…", normalized.label))

        Task {
            await startTunnelIfNeeded(for: normalized)
            await prepareWorkspaceForActiveConnection()
        }
    }

    func switchHermesProfile(to profileName: String) async {
        guard let activeConnection else { return }
        guard activeConnection.resolvedHermesProfileName != profileName else { return }

        if hasUnsavedFileChanges {
            activeAlert = AppAlert(
                title: L10n.string("Unsaved file edits"),
                message: L10n.string("Save or discard Workspace Files edits before switching Hermes profiles.")
            )
            return
        }

        let updatedConnection = activeConnection.applyingHermesProfile(named: profileName)
        let shouldCarryTerminalWorkspace = selectedSection == .terminal || terminalWorkspace.hasTabs

        if shouldCarryTerminalWorkspace {
            terminalWorkspace.ensureInitialTab(for: updatedConnection)
        }

        connectionStore.upsert(updatedConnection)
        await reloadWorkspaceScope(
            section: selectedSection,
            statusMessage: L10n.string("Switching to %@…", profileName)
        )
    }

    func testConnection(_ profile: ConnectionProfile) {
        let requestID = UUID()
        connectionTestRequestID = requestID

        Task {
            do {
                isBusy = true
                setStatusMessage(L10n.string("Testing %@…", profile.label))

                let script = try RemotePythonScript.wrap(
                    ConnectionTestRequest(),
                    body: """
                    import json
                    import pathlib
                    import sys

                    print(json.dumps({
                        "ok": True,
                        "remote_home": str(pathlib.Path.home()),
                        "python_executable": sys.executable,
                    }, ensure_ascii=False))
                    """
                )

                let response = try await sshTransport.executeJSON(
                    on: profile,
                    pythonScript: script,
                    responseType: ConnectionTestResponse.self
                )

                guard connectionTestRequestID == requestID else { return }
                isBusy = false
                let home = response.remoteHome.trimmingCharacters(in: .whitespacesAndNewlines)
                setStatusMessage(L10n.string("SSH and python3 OK for %@", profile.label))
                let messageLines = [
                    L10n.string("SSH and python3 are available for this Hermes host."),
                    home.isEmpty ? nil : L10n.string("Remote HOME: %@", home)
                ].compactMap { $0 }
                activeAlert = AppAlert(
                    title: L10n.string("Connection OK"),
                    message: messageLines.joined(separator: "\n")
                )
            } catch {
                guard connectionTestRequestID == requestID else { return }
                isBusy = false
                activeAlert = AppAlert(
                    title: L10n.string("Connection failed"),
                    message: error.localizedDescription
                )
            }
        }
    }

    func refreshOverview(manual: Bool = false) async {
        guard let profile = activeConnection else { return }
        if manual {
            guard !isRefreshingOverview, !isBusy else { return }
            isRefreshingOverview = true
        }

        do {
            isBusy = true
            overviewError = nil
            let discovery = try await remoteHermesService.discover(connection: profile)
            guard isActiveWorkspace(profile) else { return }
            overview = discovery
            isBusy = false
            if manual {
                isRefreshingOverview = false
            }
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isBusy = false
            if manual {
                isRefreshingOverview = false
            }
            overview = nil
            overviewError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to refresh remote discovery"))
        }
    }

    func refreshSessions(query: String? = nil) async {
        guard !isLoadingSessions, !isRefreshingSessions else { return }
        isRefreshingSessions = true
        await loadSessions(reset: true, query: query)
        isRefreshingSessions = false
    }

    func refreshUsage() async {
        guard !isLoadingUsage, !isRefreshingUsage else { return }
        isRefreshingUsage = true
        await loadUsage(forceRefresh: true)
        isRefreshingUsage = false
    }

    func refreshAnalytics() async {
        guard !isLoadingAnalytics, !isRefreshingAnalytics else { return }
        isRefreshingAnalytics = true
        await loadAnalytics(forceRefresh: true)
        await loadModelsAnalytics(forceRefresh: true)
        isRefreshingAnalytics = false
    }

    func loadAnalytics(forceRefresh: Bool = false) async {
        guard let profile = activeConnection else { return }
        if isLoadingAnalytics { return }
        guard forceRefresh || analyticsResponse == nil else { return }

        isLoadingAnalytics = true
        analyticsError = nil

        do {
            let response = try await dashboardAPIService.fetchAnalyticsUsage(days: analyticsDays)
            guard isActiveWorkspace(profile) else { return }
            analyticsResponse = response
            isLoadingAnalytics = false
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingAnalytics = false
            analyticsResponse = nil
            analyticsError = error.localizedDescription
        }
    }

    func loadModelsAnalytics(forceRefresh: Bool = false) async {
        guard let profile = activeConnection else { return }
        if isLoadingAnalytics { return }
        guard forceRefresh || modelsAnalyticsResponse == nil else { return }

        isLoadingAnalytics = true
        analyticsError = nil

        do {
            let response = try await dashboardAPIService.fetchModelsAnalytics(days: analyticsDays)
            guard isActiveWorkspace(profile) else { return }
            modelsAnalyticsResponse = response
            isLoadingAnalytics = false
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingAnalytics = false
            modelsAnalyticsResponse = nil
            analyticsError = error.localizedDescription
        }
    }

    func refreshSkills() async {
        guard !isLoadingSkills, !isRefreshingSkills else { return }
        isRefreshingSkills = true
        await loadSkills(reset: true)
        isRefreshingSkills = false
    }

    func refreshWorkflows() async {
        loadWorkflows(reset: true)
        await loadSkills(reset: false)
        loadWorkflows(reset: true)
    }

    func refreshCronJobs() async {
        guard !isLoadingCronJobs, !isRefreshingCronJobs else { return }
        isRefreshingCronJobs = true
        await loadCronJobs()
        isRefreshingCronJobs = false
    }

    func refreshKanbanBoard(includeArchived: Bool? = nil) async {
        guard !isLoadingKanbanBoard, !isRefreshingKanbanBoard else { return }
        isRefreshingKanbanBoard = true
        await loadKanbanBoards()
        await loadKanbanBoard(includeArchived: includeArchived)
        isRefreshingKanbanBoard = false
    }

    func workspaceFileDocument(for fileID: String) -> FileEditorDocument? {
        workspaceFileDocuments[fileID]
    }

    func selectWorkspaceFile(_ fileID: String) {
        guard workspaceFileReferences.contains(where: { $0.id == fileID }) else { return }
        selectedWorkspaceFileID = fileID
    }

    func loadSelectedWorkspaceFile(forceReload: Bool = false) async {
        guard let reference = selectedWorkspaceFileReference else { return }
        selectedWorkspaceFileID = reference.id
        await loadWorkspaceFile(reference, forceReload: forceReload)
    }

    func loadWorkspaceFile(_ reference: WorkspaceFileReference, forceReload: Bool = false) async {
        guard let profile = activeConnection else { return }
        var document = document(for: reference)

        if document.hasLoaded && !forceReload {
            setDocument(document)
            return
        }

        document.isLoading = true
        document.errorMessage = nil
        setDocument(document)

        do {
            let snapshot = try await fileEditorService.read(
                remotePath: reference.remotePath,
                connection: profile
            )
            guard isActiveWorkspace(profile) else { return }
            document.content = snapshot.content
            document.originalContent = snapshot.content
            document.remoteContentHash = snapshot.contentHash
            document.lastSavedAt = nil
            document.errorMessage = nil
            document.isLoading = false
            document.hasLoaded = true
            setDocument(document)
        } catch {
            guard isActiveWorkspace(profile) else { return }
            document.isLoading = false
            document.errorMessage = error.localizedDescription
            setDocument(document)
        }
    }

    func saveSelectedWorkspaceFile() async {
        await saveWorkspaceFile(fileID: selectedWorkspaceFileID)
    }

    func saveWorkspaceFile(fileID: String) async {
        guard let profile = activeConnection else { return }
        guard let reference = workspaceFileReferences.first(where: { $0.id == fileID }) else { return }
        var document = document(for: reference)
        guard document.hasLoaded, document.remoteContentHash != nil else {
            document.errorMessage = L10n.string("Reload the file before saving.")
            setDocument(document)
            setStatusMessage(document.errorMessage)
            return
        }

        document.isLoading = true
        document.errorMessage = nil
        setDocument(document)

        do {
            let saveResult = try await fileEditorService.write(
                remotePath: reference.remotePath,
                content: document.content,
                expectedContentHash: document.remoteContentHash,
                connection: profile
            )
            guard isActiveWorkspace(profile) else { return }
            document.originalContent = document.content
            document.remoteContentHash = saveResult.contentHash
            document.lastSavedAt = Date()
            document.hasLoaded = true
            document.isLoading = false
            setDocument(document)
            setStatusMessage(L10n.string("%@ saved", reference.title))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            document.isLoading = false
            document.errorMessage = error.localizedDescription
            setDocument(document)
            setStatusMessage(error.localizedDescription)
        }
    }

    func updateWorkspaceFile(_ fileID: String, content: String) {
        guard let reference = workspaceFileReferences.first(where: { $0.id == fileID }) else { return }
        var document = document(for: reference)
        document.content = content
        setDocument(document)
    }

    func discardWorkspaceFile(_ fileID: String) {
        var document = workspaceFileDocuments[fileID]
        document?.discardChanges()
        workspaceFileDocuments[fileID] = document
    }

    @discardableResult
    func addWorkspaceFileBookmark(
        remotePath: String,
        title: String? = nil,
        selectAfterAdd: Bool = true
    ) -> WorkspaceFileBookmark? {
        guard let activeConnection else { return nil }
        guard let bookmark = connectionStore.upsertWorkspaceFileBookmark(
            remotePath: remotePath,
            title: title,
            workspaceScopeFingerprint: activeConnection.workspaceScopeFingerprint
        ) else {
            return nil
        }

        let reference = WorkspaceFileReference.bookmark(bookmark)
        if selectAfterAdd {
            selectedWorkspaceFileID = reference.id
            workspaceFileDocuments[reference.id] = workspaceFileDocuments[reference.id] ??
                FileEditorDocument(fileID: reference.id, title: reference.title, remotePath: reference.remotePath)
        }
        setStatusMessage(L10n.string("%@ added to Workspace Files", reference.title))
        return bookmark
    }

    func removeWorkspaceFileBookmark(id: UUID) {
        connectionStore.removeWorkspaceFileBookmark(id: id)
        workspaceFileDocuments.removeValue(forKey: "bookmark:\(id.uuidString)")

        if selectedWorkspaceFileID == "bookmark:\(id.uuidString)" {
            selectedWorkspaceFileID = RemoteTrackedFile.memory.workspaceFileID
        }

        setStatusMessage(L10n.string("Bookmark removed"))
    }

    func isSessionPinned(_ sessionID: String) -> Bool {
        guard let activeConnection else { return false }
        return connectionStore.isSessionPinned(
            id: sessionID,
            workspaceScopeFingerprint: activeConnection.workspaceScopeFingerprint
        )
    }

    func pinSession(_ session: SessionSummary) {
        guard let activeConnection else { return }
        connectionStore.upsertPinnedSession(
            session,
            workspaceScopeFingerprint: activeConnection.workspaceScopeFingerprint
        )
        sessionPinStateVersion &+= 1
    }

    func unpinSession(_ session: SessionSummary) {
        guard let activeConnection else { return }
        connectionStore.removePinnedSession(
            id: session.id,
            workspaceScopeFingerprint: activeConnection.workspaceScopeFingerprint
        )
        sessionPinStateVersion &+= 1
    }

    func toggleSessionPin(_ session: SessionSummary) {
        if isSessionPinned(session.id) {
            unpinSession(session)
        } else {
            pinSession(session)
        }
    }

    func sessionSummary(for sessionID: String) -> SessionSummary? {
        sessions.first(where: { $0.id == sessionID }) ??
            pinnedSessionSummaries.first(where: { $0.id == sessionID })
    }

    func browseWorkspaceDirectory(path: String? = nil) async {
        guard let profile = activeConnection else { return }
        let trimmedPath = path?.trimmingCharacters(in: .whitespacesAndNewlines)
        let browsePath = trimmedPath?.isEmpty == false ? trimmedPath! : workspaceFileBrowserDefaultPath

        isLoadingWorkspaceFileBrowser = true
        workspaceFileBrowserError = nil

        do {
            let listing = try await fileEditorService.listDirectory(
                remotePath: browsePath,
                hermesHome: overview?.hermesHome ?? profile.remoteHermesHomePath,
                connection: profile
            )
            guard isActiveWorkspace(profile) else { return }
            workspaceFileBrowserListing = listing
            isLoadingWorkspaceFileBrowser = false
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingWorkspaceFileBrowser = false
            workspaceFileBrowserError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to browse remote files"))
        }
    }

    func loadSessions(
        reset: Bool = false,
        query: String? = nil,
        preferredSessionID: String? = nil,
        allowsFallbackSelection: Bool = true
    ) async {
        guard let profile = activeConnection else { return }

        let normalizedQuery = query?.trimmingCharacters(in: .whitespacesAndNewlines) ?? sessionSearchQuery
        if isLoadingSessions {
            if reset, query != nil {
                sessionSearchQuery = normalizedQuery
                pendingSessionReloadQuery = normalizedQuery
            }
            return
        }

        let previousSelectedSessionID = selectedSessionID

        isLoadingSessions = true
        sessionsError = nil

        if reset, query != nil {
            sessionSearchQuery = normalizedQuery
        }

        do {
            let page = try await sessionBrowserService.listSessions(
                connection: profile,
                offset: reset ? 0 : sessionOffset,
                limit: sessionPageSize,
                query: normalizedQuery
            )
            guard isActiveWorkspace(profile) else { return }

            if reset {
                sessions = page.items
                sessionOffset = page.items.count
            } else {
                sessions.append(contentsOf: page.items)
                sessionOffset += page.items.count
            }

            totalSessionsCount = page.totalCount
            hasMoreSessions = sessionOffset < totalSessionsCount
            isLoadingSessions = false

            if reset {
                let resolvedPreferredSessionID: String?
                if let explicitPreferredSessionID = preferredSessionID,
                   sessions.contains(where: { $0.id == explicitPreferredSessionID }) ||
                    isSessionPinned(explicitPreferredSessionID) {
                    resolvedPreferredSessionID = explicitPreferredSessionID
                } else if isNewSessionComposerActive {
                    resolvedPreferredSessionID = nil
                } else if let previousSelectedSessionID,
                   sessions.contains(where: { $0.id == previousSelectedSessionID }) ||
                    isSessionPinned(previousSelectedSessionID) {
                    resolvedPreferredSessionID = previousSelectedSessionID
                } else if !allowsFallbackSelection {
                    resolvedPreferredSessionID = nil
                } else {
                    resolvedPreferredSessionID = normalizedQuery.isEmpty
                        ? pinnedSessionSummaries.first?.id ?? sessions.first?.id
                        : sessions.first?.id
                }

                if let resolvedPreferredSessionID {
                    await loadSessionDetail(sessionID: resolvedPreferredSessionID)
                } else {
                    selectedSessionID = nil
                    clearSessionMessages()
                }
            }
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingSessions = false
            sessionsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load sessions"))
        }

        guard let queuedQuery = pendingSessionReloadQuery else { return }
        pendingSessionReloadQuery = nil
        guard queuedQuery != normalizedQuery else { return }
        await loadSessions(reset: true, query: queuedQuery)
    }

    func loadSessionDetail(sessionID: String) async {
        guard let profile = activeConnection else { return }
        if selectedSessionID != sessionID {
            clearSessionMessages()
        }
        clearSessionScrollOffset(for: sessionID)
        isNewSessionComposerActive = false
        selectedSessionID = sessionID
        sessionsError = nil
        sessionConversationError = nil

        do {
            let messages = try await sessionBrowserService.loadTranscript(
                connection: profile,
                sessionID: sessionID
            )
            guard isActiveWorkspace(profile), selectedSessionID == sessionID else { return }
            await setSessionMessages(messages, for: profile, sessionID: sessionID)
        } catch {
            guard isActiveWorkspace(profile), selectedSessionID == sessionID else { return }
            clearSessionMessages()
            sessionsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load session transcript"))
        }
    }

    func prepareNewSessionComposer() {
        isNewSessionComposerActive = true
        selectedSessionID = nil
        clearSessionMessages()
        sessionsError = nil
        sessionConversationError = nil
    }

    func savedSessionScrollOffset(for sessionID: String) -> CGFloat? {
        sessionScrollOffsets[sessionID]
    }

    func saveSessionScrollOffset(_ offset: CGFloat?, for sessionID: String) {
        guard let offset else {
            sessionScrollOffsets.removeValue(forKey: sessionID)
            return
        }

        sessionScrollOffsets[sessionID] = offset
    }

    private func clearSessionScrollOffset(for sessionID: String) {
        sessionScrollOffsets.removeValue(forKey: sessionID)
    }

    func startNewSession(with prompt: String, autoApproveCommands: Bool) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSendingSessionMessage else { return false }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return false }

        let existingVisibleSessionIDs = Set((sessions + pinnedSessionSummaries).map(\.id))

        isSendingSessionMessage = true
        pendingSessionTurn = PendingSessionTurn(
            sessionID: nil,
            prompt: trimmedPrompt,
            autoApproveCommands: autoApproveCommands
        )
        sessionConversationError = nil
        sessionsError = nil

        do {
            let turnResult = try await hermesChatService.sendMessage(
                trimmedPrompt,
                sessionID: nil,
                connection: profile,
                autoApproveCommands: autoApproveCommands
            )
            guard isActiveWorkspace(profile) else { return false }

            isSendingSessionMessage = false
            pendingSessionTurn = nil
            sessionSearchQuery = ""
            await loadSessions(
                reset: true,
                query: "",
                preferredSessionID: turnResult.sessionID,
                allowsFallbackSelection: false
            )

            let createdSessionID = turnResult.sessionID ??
                likelyNewSessionID(
                    afterStartingWith: trimmedPrompt,
                    excluding: existingVisibleSessionIDs
                ) ??
                sessions.first?.id

            if let createdSessionID {
                await loadSessionDetail(sessionID: createdSessionID)
            }
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSendingSessionMessage = false
            pendingSessionTurn = nil
            let message = error.localizedDescription
            sessionConversationError = message
            setStatusMessage(sessionStatusMessage(forConversationError: message, fallback: "Unable to start Hermes session"))
            return false
        }
    }

    private func likelyNewSessionID(
        afterStartingWith prompt: String,
        excluding existingSessionIDs: Set<String>
    ) -> String? {
        let newSessions = sessions.filter { !existingSessionIDs.contains($0.id) }
        guard !newSessions.isEmpty else { return nil }

        let normalizedPrompt = Self.normalizedSessionSelectionText(prompt)
        guard !normalizedPrompt.isEmpty else {
            return newSessions.first?.id
        }

        return newSessions.first { summary in
            Self.sessionSummary(summary, matchesNewSessionPrompt: normalizedPrompt)
        }?.id ?? newSessions.first?.id
    }

    nonisolated private static func sessionSummary(
        _ summary: SessionSummary,
        matchesNewSessionPrompt normalizedPrompt: String
    ) -> Bool {
        [summary.title, summary.preview].contains { candidate in
            let normalizedCandidate = normalizedSessionSelectionText(candidate ?? "")
            guard !normalizedCandidate.isEmpty else { return false }

            return normalizedPrompt.hasPrefix(normalizedCandidate) ||
                normalizedCandidate.hasPrefix(normalizedPrompt) ||
                normalizedCandidate.contains(normalizedPrompt)
        }
    }

    nonisolated private static func normalizedSessionSelectionText(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    func sendMessageToSelectedSession(_ prompt: String, autoApproveCommands: Bool) async -> Bool {
        guard let profile = activeConnection,
              let selectedSessionID else {
            return false
        }
        guard !isSendingSessionMessage else { return false }

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else { return false }

        isSendingSessionMessage = true
        pendingSessionTurn = PendingSessionTurn(
            sessionID: selectedSessionID,
            prompt: trimmedPrompt,
            autoApproveCommands: autoApproveCommands
        )
        sessionConversationError = nil
        sessionsError = nil
        startSessionTranscriptPolling(sessionID: selectedSessionID, connection: profile)

        do {
            _ = try await hermesChatService.sendMessage(
                trimmedPrompt,
                sessionID: selectedSessionID,
                connection: profile,
                autoApproveCommands: autoApproveCommands
            )
            guard isActiveWorkspace(profile) else { return false }

            stopSessionTranscriptPolling()
            if self.selectedSessionID == selectedSessionID {
                await loadSessionDetail(sessionID: selectedSessionID)
            }
            isSendingSessionMessage = false
            pendingSessionTurn = nil
            await loadSessions(reset: true, query: sessionSearchQuery)
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            stopSessionTranscriptPolling()
            isSendingSessionMessage = false
            pendingSessionTurn = nil
            let message = error.localizedDescription
            sessionConversationError = message
            setStatusMessage(sessionStatusMessage(forConversationError: message, fallback: "Unable to send prompt to Hermes"))
            return false
        }
    }

    // MARK: - Streaming chat

    func streamChatMessage(_ prompt: String) async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isStreamingChat else { return }

        let baseURL = dashboardAPIService.baseURL

        chatError = nil
        isStreamingChat = true

        // Append user message
        chatMessages.append(ChatMessage(role: .user, content: trimmed))

        // Append placeholder assistant message
        let assistantID = UUID()
        chatMessages.append(ChatMessage(
            id: assistantID,
            role: .assistant,
            content: "",
            isStreaming: true
        ))

        let budgetTokens = thinkingLevel.budgetTokens
        do {
            _ = try await hermesChatService.streamMessage(
                trimmed,
                sessionID: chatSessionID,
                baseURL: baseURL,
                thinkingBudgetTokens: budgetTokens,
                onChunk: { [weak self] delta in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let idx = self.chatMessages.firstIndex(where: { $0.id == assistantID }) {
                            self.chatMessages[idx].content += delta
                        }
                    }
                },
                onSessionID: { [weak self] sid in
                    Task { @MainActor [weak self] in
                        self?.chatSessionID = sid
                    }
                },
                onToolCall: { [weak self] toolCall in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let idx = self.chatMessages.firstIndex(where: { $0.id == assistantID }) {
                            self.chatMessages[idx].toolCalls.append(toolCall)
                        }
                    }
                },
                onToolCallDone: { [weak self] toolCallID in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let msgIdx = self.chatMessages.firstIndex(where: { $0.id == assistantID }),
                           let tcIdx = self.chatMessages[msgIdx].toolCalls.firstIndex(where: { $0.id == toolCallID }) {
                            self.chatMessages[msgIdx].toolCalls[tcIdx].status = .done
                        }
                    }
                },
                onThinkingDelta: budgetTokens != nil ? { [weak self] thinkingDelta in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let idx = self.chatMessages.firstIndex(where: { $0.id == assistantID }) {
                            self.chatMessages[idx].thinkingContent = (self.chatMessages[idx].thinkingContent ?? "") + thinkingDelta
                        }
                    }
                } : nil
            )
            // Mark streaming complete
            if let idx = chatMessages.firstIndex(where: { $0.id == assistantID }) {
                chatMessages[idx].isStreaming = false
                // Mark any still-running tool calls as done
                for tcIdx in chatMessages[idx].toolCalls.indices where chatMessages[idx].toolCalls[tcIdx].status == .running {
                    chatMessages[idx].toolCalls[tcIdx].status = .done
                }
            }
            isStreamingChat = false
        } catch {
            // Streaming failed — try SSH fallback if we have an active connection
            if let idx = chatMessages.firstIndex(where: { $0.id == assistantID }) {
                chatMessages.remove(at: idx)
            }
            isStreamingChat = false

            if let profile = activeConnection {
                do {
                    let result = try await hermesChatService.sendMessage(
                        trimmed,
                        sessionID: chatSessionID,
                        connection: profile,
                        autoApproveCommands: false
                    )
                    if let sid = result.sessionID {
                        chatSessionID = sid
                    }
                    let responseText = [result.stdout, result.stderr]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    chatMessages.append(ChatMessage(
                        role: .assistant,
                        content: responseText.isEmpty ? "(No response)" : responseText
                    ))
                } catch {
                    chatError = error.localizedDescription
                    // Remove the user message we already appended so the conversation is clean
                    if let userIdx = chatMessages.lastIndex(where: { $0.role == .user && $0.content == trimmed }) {
                        chatMessages.remove(at: userIdx)
                    }
                }
            } else {
                chatError = error.localizedDescription
                if let userIdx = chatMessages.lastIndex(where: { $0.role == .user && $0.content == trimmed }) {
                    chatMessages.remove(at: userIdx)
                }
            }
        }
    }

    func deleteSession(_ session: SessionSummary) async {
        guard let profile = activeConnection else { return }
        if isDeletingSession { return }

        isDeletingSession = true
        sessionsError = nil

        do {
            try await sessionBrowserService.deleteSession(
                connection: profile,
                sessionID: session.id,
                hintedSessionStore: overview?.sessionStore
            )
            guard isActiveWorkspace(profile) else { return }

            await loadSessions(reset: true)
            await loadUsage(forceRefresh: true)
            isDeletingSession = false
            setStatusMessage(L10n.string("Session deleted locally and on the remote Hermes host"))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isDeletingSession = false
            sessionsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to delete session"))
        }
    }

    func loadUsage(forceRefresh: Bool = false) async {
        guard let profile = activeConnection else { return }
        if isLoadingUsage { return }
        if !forceRefresh {
            if usageSummary != nil || usageError != nil {
                return
            }
        }

        isLoadingUsage = true
        usageError = nil

        do {
            let summary = try await usageBrowserService.loadUsage(
                connection: profile,
                hintedSessionStore: overview?.sessionStore
            )
            guard isActiveWorkspace(profile) else { return }

            let profileBreakdown: UsageProfileBreakdown?
            if let overview,
               overview.availableProfiles.count > 1 {
                profileBreakdown = await loadUsageProfileBreakdown(
                    using: profile,
                    activeSummary: summary,
                    discoveredProfiles: overview.availableProfiles
                )
            } else {
                profileBreakdown = nil
            }
            guard isActiveWorkspace(profile) else { return }

            usageSummary = summary
            usageProfileBreakdown = profileBreakdown
            isLoadingUsage = false
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingUsage = false
            usageSummary = nil
            usageProfileBreakdown = nil
            usageError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load usage"))
        }
    }

    func loadSkills(reset: Bool = false) async {
        guard let profile = activeConnection else { return }
        if isLoadingSkills { return }

        let previousSelectedSkillID = selectedSkillID

        isLoadingSkills = true
        skillsError = nil

        do {
            let items = try await skillBrowserService.listSkills(connection: profile)
            guard isActiveWorkspace(profile) else { return }
            skills = items.sorted { lhs, rhs in
                let comparison = lhs.slug.localizedCaseInsensitiveCompare(rhs.slug)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }

                return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
            }
            isLoadingSkills = false

            if reset {
                let preferredSkillID: String?
                if let previousSelectedSkillID,
                   items.contains(where: { $0.id == previousSelectedSkillID }) {
                    preferredSkillID = previousSelectedSkillID
                } else {
                    preferredSkillID = items.first?.id
                }

                if let preferredSkill = items.first(where: { $0.id == preferredSkillID }) {
                    await loadSkillDetail(summary: preferredSkill)
                } else if let firstSkill = items.first {
                    await loadSkillDetail(summary: firstSkill)
                } else {
                    selectedSkillID = nil
                    selectedSkillDetail = nil
                    isLoadingSkillDetail = false
                }
            }
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingSkills = false
            skillsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load skills"))
        }
    }

    func loadWorkflows(reset: Bool = false) {
        guard let profile = activeConnection else {
            workflows = []
            selectedWorkflowID = nil
            return
        }

        let previousSelectedWorkflowID = selectedWorkflowID
        workflows = connectionStore.workflows(for: profile.workspaceScopeFingerprint)

        guard reset else { return }

        if let previousSelectedWorkflowID,
           workflows.contains(where: { $0.id == previousSelectedWorkflowID }) {
            selectedWorkflowID = previousSelectedWorkflowID
        } else {
            selectedWorkflowID = workflows.first?.id
        }
    }

    func createWorkflow(_ draft: WorkflowDraft) -> Bool {
        guard let profile = activeConnection else { return false }

        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            setStatusMessage(localizedError)
            activeAlert = AppAlert(
                title: L10n.string("Unable to save workflow"),
                message: localizedError
            )
            return false
        }

        let workflow = WorkflowPreset(
            workspaceScopeFingerprint: profile.workspaceScopeFingerprint,
            name: draft.normalizedName,
            prompt: draft.normalizedPrompt,
            assignedSkills: draft.normalizedSelectedSkills
        )

        connectionStore.upsertWorkflow(workflow)
        loadWorkflows(reset: true)
        selectedWorkflowID = workflow.id
        setStatusMessage(L10n.string("%@ created", workflow.name))
        return true
    }

    func updateWorkflow(_ workflow: WorkflowPreset, draft: WorkflowDraft) -> Bool {
        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            setStatusMessage(localizedError)
            activeAlert = AppAlert(
                title: L10n.string("Unable to save workflow"),
                message: localizedError
            )
            return false
        }

        let updatedWorkflow = workflow.updated(
            name: draft.normalizedName,
            prompt: draft.normalizedPrompt,
            assignedSkills: draft.normalizedSelectedSkills
        )

        connectionStore.upsertWorkflow(updatedWorkflow)
        loadWorkflows(reset: true)
        selectedWorkflowID = updatedWorkflow.id
        setStatusMessage(L10n.string("%@ updated", updatedWorkflow.name))
        return true
    }

    func deleteWorkflow(_ workflow: WorkflowPreset) {
        connectionStore.removeWorkflow(id: workflow.id)
        loadWorkflows(reset: true)
        setStatusMessage(L10n.string("%@ removed", workflow.name))
    }

    func workflow(id: UUID?) -> WorkflowPreset? {
        guard let id else { return nil }
        return workflows.first(where: { $0.id == id })
    }

    func runWorkflow(_ workflow: WorkflowPreset) async {
        guard let profile = activeConnection else {
            activeAlert = AppAlert(
                title: L10n.string("No active connection"),
                message: L10n.string("Select a connection before running a workflow.")
            )
            setStatusMessage(L10n.string("No active connection"))
            return
        }

        if skills.isEmpty && !isLoadingSkills {
            await loadSkills(reset: false)
        }

        let skillsByRelativePath = Dictionary(uniqueKeysWithValues: skills.map { ($0.relativePath, $0) })
        let missingSkills = workflow.assignedSkills.filter { skillsByRelativePath[$0.relativePath] == nil }

        guard missingSkills.isEmpty else {
            let message: String
            if let skillsError,
               skills.isEmpty {
                message = skillsError
            } else {
                message = L10n.string(
                    "This workflow references skills that are not available on the active host/profile: %@",
                    missingSkills.map(\.relativePath).joined(separator: ", ")
                )
            }

            activeAlert = AppAlert(
                title: L10n.string("Workflow cannot run"),
                message: message
            )
            setStatusMessage(L10n.string("Workflow cannot run"))
            return
        }

        let invocation = WorkflowLaunchInvocation(workflow: workflow, connection: profile)
        let workflowLaunchDiagnosticsContext = WorkflowLaunchDiagnosticsContext(
            workflow: workflow,
            invocation: invocation,
            connection: profile
        )
        await workflowLaunchDiagnostics.recordWorkflowRunRequested(workflowLaunchDiagnosticsContext)
        terminalWorkspace.addCommandTab(
            for: profile.updated(),
            commandLine: invocation.startupCommandLine,
            initialInput: invocation.initialInput,
            workflowLaunchDiagnosticsContext: workflowLaunchDiagnosticsContext
        )
        selectedSection = .terminal
        handleSectionEntry(.terminal)
        setStatusMessage(L10n.string("Opening %@ in Terminal…", workflow.name))
    }

    func loadSkillDetail(summary: SkillSummary) async {
        guard let profile = activeConnection else { return }
        let skillID = summary.id
        selectedSkillID = skillID
        selectedSkillDetail = nil
        skillsError = nil
        isLoadingSkillDetail = true

        do {
            let detail = try await skillBrowserService.loadSkillDetail(
                connection: profile,
                locator: summary.locator
            )

            guard isActiveWorkspace(profile), selectedSkillID == skillID else { return }
            selectedSkillDetail = detail
            isLoadingSkillDetail = false
        } catch {
            guard isActiveWorkspace(profile), selectedSkillID == skillID else { return }
            selectedSkillDetail = nil
            isLoadingSkillDetail = false
            skillsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load skill detail"))
        }
    }

    func createSkill(_ draft: SkillDraft) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingSkillDraft else { return false }

        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            skillsError = localizedError
            setStatusMessage(localizedError)
            return false
        }

        isSavingSkillDraft = true
        skillsError = nil
        setStatusMessage(L10n.string("Creating skill…"))

        do {
            let detail = try await skillBrowserService.createSkill(
                connection: profile,
                draft: draft
            )
            guard isActiveWorkspace(profile) else { return false }
            await loadSkills(reset: true)
            selectedSkillID = detail.id
            selectedSkillDetail = detail
            isSavingSkillDraft = false
            setStatusMessage(L10n.string("%@ created", draft.normalizedName))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSavingSkillDraft = false
            skillsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to create skill"))
            return false
        }
    }

    func updateSkill(
        _ detail: SkillDetail,
        markdownContent: String,
        ensureReferencesFolder: Bool,
        ensureScriptsFolder: Bool,
        ensureTemplatesFolder: Bool
    ) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingSkillDraft else { return false }

        let normalizedContent = markdownContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedContent.isEmpty else {
            let message = L10n.string("SKILL.md content cannot be empty.")
            skillsError = message
            setStatusMessage(message)
            return false
        }

        isSavingSkillDraft = true
        skillsError = nil
        setStatusMessage(L10n.string("Updating %@…", detail.resolvedName))

        do {
            let updatedDetail = try await skillBrowserService.updateSkill(
                connection: profile,
                locator: detail.locator,
                markdownContent: normalizedContent + "\n",
                expectedContentHash: detail.contentHash,
                ensureReferencesFolder: ensureReferencesFolder,
                ensureScriptsFolder: ensureScriptsFolder,
                ensureTemplatesFolder: ensureTemplatesFolder
            )
            guard isActiveWorkspace(profile) else { return false }
            await loadSkills(reset: true)
            selectedSkillID = updatedDetail.id
            selectedSkillDetail = updatedDetail
            isSavingSkillDraft = false
            setStatusMessage(L10n.string("%@ updated", updatedDetail.resolvedName))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSavingSkillDraft = false
            skillsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to update skill"))
            return false
        }
    }

    func loadCronJobs() async {
        guard let profile = activeConnection else { return }
        if isLoadingCronJobs { return }

        let previousSelectedCronJobID = selectedCronJobID
        isLoadingCronJobs = true
        cronJobsError = nil

        do {
            let jobs = try await cronBrowserService.listJobs(connection: profile)
            guard isActiveWorkspace(profile) else { return }
            cronJobs = jobs
            isLoadingCronJobs = false

            if let previousSelectedCronJobID,
               jobs.contains(where: { $0.id == previousSelectedCronJobID }) {
                selectedCronJobID = previousSelectedCronJobID
            } else {
                selectedCronJobID = jobs.first?.id
            }
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingCronJobs = false
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load cron jobs"))
        }
    }

    func pauseCronJob(_ job: CronJob) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnCronJob else { return }

        isOperatingOnCronJob = true
        operatingCronJobID = job.id
        cronJobsError = nil

        do {
            try await cronBrowserService.pauseJob(connection: profile, jobID: job.id)
            guard isActiveWorkspace(profile) else { return }
            await loadCronJobs()
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            setStatusMessage(L10n.string("%@ paused", job.resolvedName))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to pause cron job"))
        }
    }

    func createCronJob(_ draft: CronJobDraft) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingCronJobDraft, !isOperatingOnCronJob else { return false }

        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            cronJobsError = localizedError
            setStatusMessage(localizedError)
            return false
        }

        isSavingCronJobDraft = true
        cronJobsError = nil
        setStatusMessage(L10n.string("Creating cron job…"))

        do {
            let jobID = try await cronBrowserService.createJob(connection: profile, draft: draft)
            guard isActiveWorkspace(profile) else { return false }
            await loadCronJobs()
            selectedCronJobID = jobID
            isSavingCronJobDraft = false
            setStatusMessage(L10n.string("%@ created", draft.normalizedName))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSavingCronJobDraft = false
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to create cron job"))
            return false
        }
    }

    func updateCronJob(_ job: CronJob, draft: CronJobDraft) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingCronJobDraft, !isOperatingOnCronJob else { return false }

        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            cronJobsError = localizedError
            setStatusMessage(localizedError)
            return false
        }

        isSavingCronJobDraft = true
        cronJobsError = nil
        setStatusMessage(L10n.string("Updating %@…", job.resolvedName))

        do {
            try await cronBrowserService.updateJob(connection: profile, jobID: job.id, draft: draft)
            guard isActiveWorkspace(profile) else { return false }
            await loadCronJobs()
            selectedCronJobID = job.id
            isSavingCronJobDraft = false
            setStatusMessage(L10n.string("%@ updated", draft.normalizedName))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSavingCronJobDraft = false
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to update cron job"))
            return false
        }
    }

    func resumeCronJob(_ job: CronJob) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnCronJob else { return }

        isOperatingOnCronJob = true
        operatingCronJobID = job.id
        cronJobsError = nil

        do {
            try await cronBrowserService.resumeJob(connection: profile, jobID: job.id)
            guard isActiveWorkspace(profile) else { return }
            await loadCronJobs()
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            setStatusMessage(L10n.string("%@ resumed", job.resolvedName))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to resume cron job"))
        }
    }

    func deleteCronJob(_ job: CronJob) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnCronJob else { return }

        isOperatingOnCronJob = true
        operatingCronJobID = job.id
        cronJobsError = nil

        do {
            try await cronBrowserService.removeJob(connection: profile, jobID: job.id)
            guard isActiveWorkspace(profile) else { return }
            await loadCronJobs()
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            setStatusMessage(L10n.string("%@ removed", job.resolvedName))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to remove cron job"))
        }
    }

    func runCronJobNow(_ job: CronJob) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnCronJob else { return }

        isOperatingOnCronJob = true
        operatingCronJobID = job.id
        cronJobsError = nil
        setStatusMessage(L10n.string("Triggering %@…", job.resolvedName))

        do {
            try await cronBrowserService.runJobNow(connection: profile, jobID: job.id)
            guard isActiveWorkspace(profile) else { return }
            await loadCronJobs()
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            setStatusMessage(L10n.string("Run requested for %@", job.resolvedName))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to run cron job"))
        }
    }

    // MARK: - Dashboard Cron Jobs (Jobs tab)

    func loadDashboardCronJobs() async {
        guard dashboardAPIAvailable else { return }
        if isLoadingDashboardCronJobs { return }

        isLoadingDashboardCronJobs = true
        dashboardCronJobsError = nil

        do {
            let jobs = try await dashboardAPIService.fetchClaudeJobs()
            dashboardCronJobs = jobs
            isLoadingDashboardCronJobs = false
        } catch {
            isLoadingDashboardCronJobs = false
            dashboardCronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load jobs"))
        }
    }

    func createDashboardCronJob(_ job: DashboardCronJobCreate) async {
        guard dashboardAPIAvailable else { return }

        do {
            _ = try await dashboardAPIService.createClaudeJob(job)
            setStatusMessage(L10n.string("%@ created", job.name))
            await loadDashboardCronJobs()
        } catch {
            dashboardCronJobsError = error.localizedDescription
            setStatusMessage(error.localizedDescription)
        }
    }

    func deleteDashboardCronJob(id: String) async {
        guard dashboardAPIAvailable else { return }

        do {
            try await dashboardAPIService.deleteClaudeJob(id: id)
            dashboardCronJobs.removeAll { $0.id == id }
            setStatusMessage(L10n.string("Job removed"))
        } catch {
            dashboardCronJobsError = error.localizedDescription
            setStatusMessage(error.localizedDescription)
        }
    }

    func toggleDashboardCronJob(id: String, enabled: Bool) async {
        guard dashboardAPIAvailable else { return }

        do {
            let patch = DashboardCronJobPatch(enabled: enabled)
            let updated = try await dashboardAPIService.patchClaudeJob(id: id, patch: patch)
            if let index = dashboardCronJobs.firstIndex(where: { $0.id == id }) {
                dashboardCronJobs[index] = updated
            }
        } catch {
            dashboardCronJobsError = error.localizedDescription
            setStatusMessage(error.localizedDescription)
        }
    }

    // MARK: - MCP Servers

    func loadMCPServers() async {
        guard dashboardAPIAvailable else { return }
        if isLoadingMCP { return }

        isLoadingMCP = true
        mcpError = nil

        do {
            let servers = try await dashboardAPIService.fetchMCPServers()
            mcpServers = servers
            isLoadingMCP = false
        } catch {
            isLoadingMCP = false
            mcpError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load MCP servers"))
        }
    }

    func searchMCPMarketplace(query: String) async {
        guard dashboardAPIAvailable else { return }

        do {
            let items = try await dashboardAPIService.searchMCPHub(query: query)
            mcpMarketplaceItems = items
        } catch {
            mcpError = error.localizedDescription
        }
    }

    func addMCPServer(_ server: MCPServerCreate) async {
        guard dashboardAPIAvailable else { return }

        do {
            let created = try await dashboardAPIService.createMCPServer(server)
            mcpServers.append(created)
            setStatusMessage(L10n.string("%@ added", server.name))
        } catch {
            mcpError = error.localizedDescription
            setStatusMessage(error.localizedDescription)
        }
    }

    func deleteMCPServer(id: String) async {
        guard dashboardAPIAvailable else { return }

        do {
            try await dashboardAPIService.deleteMCPServer(id: id)
            mcpServers.removeAll { $0.id == id }
            setStatusMessage(L10n.string("Server removed"))
        } catch {
            mcpError = error.localizedDescription
            setStatusMessage(error.localizedDescription)
        }
    }

    func loadKanbanBoards() async {
        guard let profile = activeConnection else { return }
        if isLoadingKanbanBoards { return }

        isLoadingKanbanBoards = true
        kanbanError = nil

        do {
            let response = try await kanbanBrowserService.loadBoards(connection: profile)
            guard isActiveWorkspace(profile) else { return }

            kanbanBoards = response.boards.isEmpty
                ? [KanbanProject(slug: KanbanProject.defaultSlug)]
                : response.boards
            remoteCurrentKanbanBoardSlug = response.current
            supportsKanbanBoardManagement = response.supportsBoardManagement

            if !kanbanBoards.contains(where: { $0.slug == selectedKanbanBoardSlug }) {
                if let current = response.current,
                   kanbanBoards.contains(where: { $0.slug == current }) {
                    selectedKanbanBoardSlug = current
                } else {
                    selectedKanbanBoardSlug = kanbanBoards.first?.slug ?? KanbanProject.defaultSlug
                }
            }

            isLoadingKanbanBoards = false
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingKanbanBoards = false
            kanbanBoards = kanbanBoards.isEmpty ? [KanbanProject(slug: KanbanProject.defaultSlug)] : kanbanBoards
            remoteCurrentKanbanBoardSlug = nil
            supportsKanbanBoardManagement = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load Kanban boards"))
        }
    }

    func selectKanbanBoard(_ slug: String) async {
        let normalizedSlug = slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedSlug.isEmpty else { return }
        guard selectedKanbanBoardSlug != normalizedSlug else { return }
        guard kanbanBoards.isEmpty || kanbanBoards.contains(where: { $0.slug == normalizedSlug }) else { return }

        selectedKanbanBoardSlug = normalizedSlug
        selectedKanbanTaskID = nil
        selectedKanbanTaskDetail = nil
        kanbanBoard = nil
        await loadKanbanBoard()
    }

    func loadKanbanBoard(includeArchived: Bool? = nil) async {
        guard let profile = activeConnection else { return }
        if isLoadingKanbanBoard { return }

        if let includeArchived {
            includeArchivedKanbanTasks = includeArchived
        }

        if kanbanBoards.isEmpty, !isLoadingKanbanBoards {
            await loadKanbanBoards()
        }

        let boardSlug = selectedKanbanBoardSlug
        let previousSelectedTaskID = selectedKanbanTaskID
        isLoadingKanbanBoard = true
        kanbanError = nil

        do {
            let board = try await kanbanBrowserService.loadBoard(
                connection: profile,
                boardSlug: boardSlug,
                includeArchived: includeArchivedKanbanTasks
            )
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return }
            kanbanBoard = board
            isLoadingKanbanBoard = false

            let nextSelectedTaskID: String?
            if let previousSelectedTaskID,
               board.tasks.contains(where: { $0.id == previousSelectedTaskID }) {
                nextSelectedTaskID = previousSelectedTaskID
            } else {
                nextSelectedTaskID = board.tasks.first?.id
            }

            selectedKanbanTaskID = nextSelectedTaskID
            if let nextSelectedTaskID {
                await loadKanbanTaskDetail(taskID: nextSelectedTaskID)
            } else {
                selectedKanbanTaskDetail = nil
            }
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingKanbanBoard = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load Kanban board"))
        }
    }

    func loadKanbanTaskDetail(taskID: String) async {
        guard let profile = activeConnection else { return }
        let boardSlug = selectedKanbanBoardSlug

        selectedKanbanTaskID = taskID
        isLoadingKanbanTaskDetail = true
        kanbanError = nil

        do {
            let detail = try await kanbanBrowserService.loadTaskDetail(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID
            )
            guard isActiveWorkspace(profile),
                  selectedKanbanBoardSlug == boardSlug,
                  selectedKanbanTaskID == taskID else { return }
            selectedKanbanTaskDetail = detail
            isLoadingKanbanTaskDetail = false
        } catch {
            guard isActiveWorkspace(profile),
                  selectedKanbanBoardSlug == boardSlug,
                  selectedKanbanTaskID == taskID else { return }
            selectedKanbanTaskDetail = nil
            isLoadingKanbanTaskDetail = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load Kanban task"))
        }
    }

    func createKanbanBoard(_ draft: KanbanBoardDraft) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingKanbanBoardDraft, !isOperatingOnKanbanBoard else { return false }

        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            kanbanError = localizedError
            setStatusMessage(localizedError)
            return false
        }

        isSavingKanbanBoardDraft = true
        kanbanError = nil
        setStatusMessage(L10n.string("Creating Kanban board..."))

        do {
            let board = try await kanbanBrowserService.createBoard(connection: profile, draft: draft)
            guard isActiveWorkspace(profile) else { return false }
            await loadKanbanBoards()
            selectedKanbanBoardSlug = board.slug
            selectedKanbanTaskID = nil
            selectedKanbanTaskDetail = nil
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            isSavingKanbanBoardDraft = false
            setStatusMessage(L10n.string("%@ created", board.resolvedName))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSavingKanbanBoardDraft = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to create Kanban board"))
            return false
        }
    }

    func archiveKanbanBoard(_ board: KanbanProject) async {
        guard let profile = activeConnection else { return }
        guard !board.isDefault, !isOperatingOnKanbanBoard else { return }

        isOperatingOnKanbanBoard = true
        kanbanError = nil
        setStatusMessage(L10n.string("Archiving %@...", board.resolvedName))

        do {
            try await kanbanBrowserService.archiveBoard(connection: profile, slug: board.slug)
            guard isActiveWorkspace(profile) else { return }
            if selectedKanbanBoardSlug == board.slug {
                selectedKanbanBoardSlug = KanbanProject.defaultSlug
                selectedKanbanTaskID = nil
                selectedKanbanTaskDetail = nil
                kanbanBoard = nil
            }
            await loadKanbanBoards()
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            isOperatingOnKanbanBoard = false
            setStatusMessage(L10n.string("%@ archived", board.resolvedName))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnKanbanBoard = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to archive Kanban board"))
        }
    }

    func createKanbanTask(_ draft: KanbanTaskDraft) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingKanbanTaskDraft, !isOperatingOnKanbanTask else { return false }

        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            kanbanError = localizedError
            setStatusMessage(localizedError)
            return false
        }

        isSavingKanbanTaskDraft = true
        kanbanError = nil
        setStatusMessage(L10n.string("Creating Kanban task..."))

        do {
            let boardSlug = selectedKanbanBoardSlug
            let taskID = try await kanbanBrowserService.createTask(connection: profile, boardSlug: boardSlug, draft: draft)
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return false }
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            selectedKanbanTaskID = taskID
            await loadKanbanTaskDetail(taskID: taskID)
            isSavingKanbanTaskDraft = false
            setStatusMessage(L10n.string("Kanban task created"))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSavingKanbanTaskDraft = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to create Kanban task"))
            return false
        }
    }

    func addKanbanComment(taskID: String, body: String) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isOperatingOnKanbanTask else { return false }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskID
        kanbanError = nil

        do {
            let boardSlug = selectedKanbanBoardSlug
            try await kanbanBrowserService.addComment(connection: profile, boardSlug: boardSlug, taskID: taskID, body: trimmed)
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return false }
            await reloadKanbanAfterOperation(taskID: taskID, boardSlug: boardSlug)
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            setStatusMessage(L10n.string("Comment added"))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to add Kanban comment"))
            return false
        }
    }

    func updateKanbanTaskFields(
        taskID: String,
        body: String,
        tenant: String,
        priority: Int,
        skills: [String]
    ) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task details updated",
            failureMessage: "Unable to update Kanban task details"
        ) { profile, boardSlug in
            try await kanbanBrowserService.updateTaskFields(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                body: body,
                tenant: tenant,
                priority: priority,
                skills: skills
            )
        }
    }

    func setKanbanTaskParents(taskID: String, parentIDs: [String]) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task parents updated",
            failureMessage: "Unable to update Kanban task parents"
        ) { profile, boardSlug in
            try await kanbanBrowserService.setTaskParents(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                parentIDs: parentIDs
            )
        }
    }

    func setKanbanTaskChildren(taskID: String, childIDs: [String]) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task children updated",
            failureMessage: "Unable to update Kanban task children"
        ) { profile, boardSlug in
            try await kanbanBrowserService.setTaskChildren(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                childIDs: childIDs
            )
        }
    }

    func assignKanbanTask(taskID: String, assignee: String?) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task assigned",
            failureMessage: "Unable to assign Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.assignTask(connection: profile, boardSlug: boardSlug, taskID: taskID, assignee: assignee)
        }
    }

    func specifyKanbanTask(taskID: String) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task specified",
            failureMessage: "Unable to specify Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.specifyTask(connection: profile, boardSlug: boardSlug, taskID: taskID)
        }
    }

    func blockKanbanTask(taskID: String, reason: String?) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task blocked",
            failureMessage: "Unable to block Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.blockTask(connection: profile, boardSlug: boardSlug, taskID: taskID, reason: reason)
        }
    }

    func unblockKanbanTask(taskID: String) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task unblocked",
            failureMessage: "Unable to unblock Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.unblockTask(connection: profile, boardSlug: boardSlug, taskID: taskID)
        }
    }

    func completeKanbanTask(taskID: String, result: String?) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task completed",
            failureMessage: "Unable to complete Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.completeTask(connection: profile, boardSlug: boardSlug, taskID: taskID, result: result)
        }
    }

    func moveKanbanTask(taskID: String, toStatus newStatus: KanbanTaskStatus) async {
        guard dashboardAPIAvailable else { return }
        let boardSlug = selectedKanbanBoardSlug

        // Optimistic update
        var revertTasks: [KanbanTask]?
        if var board = kanbanBoard {
            revertTasks = board.tasks
            if let idx = board.tasks.firstIndex(where: { $0.id == taskID }) {
                var updated = board.tasks[idx]
                updated = KanbanTask(
                    id: updated.id,
                    title: updated.title,
                    body: updated.body,
                    status: newStatus,
                    priority: updated.priority,
                    assignee: updated.assignee,
                    tenant: updated.tenant,
                    skills: updated.skills,
                    parentIDs: updated.parentIDs,
                    childIDs: updated.childIDs,
                    createdAt: updated.createdAt,
                    updatedAt: updated.updatedAt
                )
                board.tasks[idx] = updated
                kanbanBoard = board
            }
        }

        do {
            try await dashboardAPIService.kanbanMoveTask(
                boardSlug: boardSlug,
                taskID: taskID,
                statusRawValue: newStatus.rawValue
            )
            await reloadKanbanAfterOperation(taskID: taskID, boardSlug: boardSlug)
        } catch {
            // Revert optimistic update on failure
            if var board = kanbanBoard, let revert = revertTasks {
                board.tasks = revert
                kanbanBoard = board
            }
            kanbanError = error.localizedDescription
        }
    }

    func reclaimKanbanTask(taskID: String, reason: String?) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task reclaimed",
            failureMessage: "Unable to reclaim Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.reclaimTask(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                reason: reason
            )
        }
    }

    func reassignKanbanTask(taskID: String, assignee: String?, reclaimFirst: Bool, reason: String?) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task reassigned",
            failureMessage: "Unable to reassign Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.reassignTask(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                assignee: assignee,
                reclaimFirst: reclaimFirst,
                reason: reason
            )
        }
    }

    func editKanbanTaskResult(taskID: String, result: String, summary: String?, metadataJSON: String?) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task result edited",
            failureMessage: "Unable to edit Kanban task result"
        ) { profile, boardSlug in
            try await kanbanBrowserService.editCompletedTaskResult(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                result: result,
                summary: summary,
                metadataJSON: metadataJSON
            )
        }
    }

    func archiveKanbanTask(taskID: String) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task archived",
            failureMessage: "Unable to archive Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.archiveTask(connection: profile, boardSlug: boardSlug, taskID: taskID)
        }
    }

    func deleteKanbanTask(taskID: String) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnKanbanTask else { return }

        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskID
        kanbanError = nil

        do {
            let boardSlug = selectedKanbanBoardSlug
            try await kanbanBrowserService.deleteTask(connection: profile, boardSlug: boardSlug, taskID: taskID)
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return }
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            if selectedKanbanTaskID == nil {
                selectedKanbanTaskDetail = nil
            }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            setStatusMessage(L10n.string("Kanban task deleted"))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to delete Kanban task"))
        }
    }

    func dispatchKanbanNow() async {
        guard let profile = activeConnection else { return }
        guard !isDispatchingKanban else { return }

        isDispatchingKanban = true
        kanbanError = nil
        setStatusMessage(L10n.string("Nudging Kanban dispatcher..."))

        do {
            let boardSlug = selectedKanbanBoardSlug
            let result = try await kanbanBrowserService.dispatchNow(connection: profile, boardSlug: boardSlug)
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return }
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            isDispatchingKanban = false

            if let result {
                setStatusMessage(
                    L10n.string(
                        "Kanban dispatch: %@ spawned, %@ promoted",
                        "\(result.spawned.count)",
                        "\(result.promoted)"
                    )
                )
            } else {
                setStatusMessage(L10n.string("Kanban dispatcher nudged"))
            }
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isDispatchingKanban = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to nudge Kanban dispatcher"))
        }
    }

    func setKanbanHomeSubscription(
        taskID: String,
        homeChannel: KanbanHomeChannel,
        subscribed: Bool
    ) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isOperatingOnKanbanTask else { return false }

        let boardSlug = selectedKanbanBoardSlug
        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskID
        kanbanError = nil

        do {
            try await kanbanBrowserService.setHomeSubscription(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                homeChannel: homeChannel,
                subscribed: subscribed
            )
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return false }
            await loadKanbanTaskDetail(taskID: taskID)
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            setStatusMessage(subscribed ? L10n.string("Home channel subscribed") : L10n.string("Home channel unsubscribed"))
            return true
        } catch {
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return false }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to update Kanban home channel"))
            return false
        }
    }

    // MARK: - Kanban Plugin: Decompose, Log, Orchestration, Bulk

    /// POST /api/plugins/kanban/tasks/{task_id}/decompose
    /// Decomposes the selected task into subtasks via LLM. HTTP-only (requires dashboard access).
    func decomposeKanbanTask(_ taskID: String) async {
        guard dashboardAPIAvailable else {
            kanbanError = L10n.string("Dashboard API is not available. Connect via SSH tunnel or local connection to use decompose.")
            return
        }
        let boardSlug = selectedKanbanBoardSlug
        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskID
        kanbanError = nil
        setStatusMessage(L10n.string("Decomposing task…"))

        do {
            try await dashboardAPIService.kanbanDecomposeTask(taskID: taskID, boardSlug: boardSlug)
            await reloadKanbanAfterOperation(taskID: taskID, boardSlug: boardSlug)
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            setStatusMessage(L10n.string("Task decomposed into subtasks"))
        } catch {
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to decompose task"))
        }
    }

    /// GET /api/plugins/kanban/tasks/{task_id}/log
    /// Loads the worker stdout/stderr log for the given task. Prefers HTTP; falls back to the
    /// workerLog field already present in task detail (SSH path).
    func viewKanbanTaskLog(_ taskID: String) async {
        guard !isLoadingKanbanLog else { return }
        kanbanTaskLog = nil
        isLoadingKanbanLog = true
        kanbanError = nil

        // Prefer HTTP API when dashboard is available
        if dashboardAPIAvailable {
            let boardSlug = selectedKanbanBoardSlug
            do {
                let log = try await dashboardAPIService.kanbanGetTaskLog(taskID: taskID, boardSlug: boardSlug)
                isLoadingKanbanLog = false
                kanbanTaskLog = log.isEmpty ? L10n.string("(No log output)") : log
                return
            } catch {
                // Fall through to SSH path
            }
        }

        // SSH fallback: use the workerLog already loaded in selectedKanbanTaskDetail
        if let existingLog = selectedKanbanTaskDetail?.workerLog,
           !existingLog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            kanbanTaskLog = existingLog
            isLoadingKanbanLog = false
            return
        }

        // Try reloading task detail over SSH to pick up workerLog
        if let profile = activeConnection {
            let boardSlug = selectedKanbanBoardSlug
            do {
                let detail = try await kanbanBrowserService.loadTaskDetail(
                    connection: profile,
                    boardSlug: boardSlug,
                    taskID: taskID
                )
                isLoadingKanbanLog = false
                let trimmedLog = detail.workerLog?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                kanbanTaskLog = trimmedLog.isEmpty ? L10n.string("(No log output)") : trimmedLog
                return
            } catch {
                isLoadingKanbanLog = false
                kanbanTaskLog = nil
                kanbanError = error.localizedDescription
                return
            }
        }

        isLoadingKanbanLog = false
        kanbanTaskLog = L10n.string("(No log output)")
    }

    /// GET /api/plugins/kanban/orchestration
    /// Loads orchestration config. Requires dashboard API access.
    func loadKanbanOrchestration() async {
        guard dashboardAPIAvailable else { return }
        guard !isLoadingKanbanOrchestration else { return }

        isLoadingKanbanOrchestration = true
        kanbanOrchestrationError = nil

        do {
            let config = try await dashboardAPIService.kanbanGetOrchestration()
            isLoadingKanbanOrchestration = false
            kanbanOrchestration = config
        } catch {
            isLoadingKanbanOrchestration = false
            kanbanOrchestrationError = error.localizedDescription
        }
    }

    /// PUT /api/plugins/kanban/orchestration
    /// Saves orchestration config. Requires dashboard API access.
    func saveKanbanOrchestration(_ config: KanbanOrchestrationConfig) async {
        guard dashboardAPIAvailable else { return }

        isLoadingKanbanOrchestration = true
        kanbanOrchestrationError = nil
        setStatusMessage(L10n.string("Saving orchestration config…"))

        do {
            try await dashboardAPIService.kanbanUpdateOrchestration(config)
            kanbanOrchestration = config
            isLoadingKanbanOrchestration = false
            setStatusMessage(L10n.string("Orchestration config saved"))
        } catch {
            isLoadingKanbanOrchestration = false
            kanbanOrchestrationError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to save orchestration config"))
        }
    }

    /// POST /api/plugins/kanban/tasks/bulk (HTTP) or individual SSH moves (fallback)
    func bulkUpdateKanbanTasks(_ taskIDs: [String], status: KanbanTaskStatus) async {
        guard !taskIDs.isEmpty else { return }
        let boardSlug = selectedKanbanBoardSlug
        kanbanError = nil

        if dashboardAPIAvailable {
            setStatusMessage(L10n.string("Updating %@ tasks…", "\(taskIDs.count)"))
            do {
                try await dashboardAPIService.kanbanBulkUpdateTasks(
                    taskIDs: taskIDs,
                    status: status,
                    boardSlug: boardSlug
                )
                kanbanSelectedTaskIDs = []
                await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
                setStatusMessage(L10n.string("Moved %@ tasks to %@", "\(taskIDs.count)", status.displayTitle))
            } catch {
                kanbanError = error.localizedDescription
                setStatusMessage(L10n.string("Bulk update failed"))
            }
        } else {
            // Bulk status change requires dashboard API. Show a helpful error.
            kanbanError = L10n.string("Bulk status update requires dashboard API access. Enable SSH tunnel or use a local connection.")
            setStatusMessage(L10n.string("Dashboard API required for bulk update"))
        }
    }

    func deleteConnection(_ profile: ConnectionProfile) {
        connectionStore.delete(profile)
        terminalWorkspace.closeTabs(forConnectionID: profile.id)
        if activeConnectionID == profile.id {
            activeConnectionID = nil
            resetWorkspaceStateForConnectionChange(closeTerminalTabs: false)
            selectedSection = .connections
        }
    }

    func ensureTerminalSession() {
        guard let profile = activeConnection else { return }
        terminalWorkspace.ensureInitialTab(for: profile)
    }

    private func openNewTerminalTab(for profile: ConnectionProfile) {
        terminalWorkspace.addTab(for: profile)
        selectedSection = .terminal
        handleSectionEntry(.terminal)
        setStatusMessage(L10n.string("New Terminal tab opened"))
    }

    func resumeSessionInTerminal(_ session: SessionSummary) {
        guard let profile = activeConnection else {
            sessionsError = L10n.string("Select a connection before resuming a session in Terminal.")
            setStatusMessage(L10n.string("No active connection"))
            return
        }

        let invocation = HermesSessionResumeInvocation(sessionID: session.id, connection: profile)
        terminalWorkspace.addCommandTab(
            for: profile.updated(),
            commandLine: invocation.startupCommandLine
        )
        selectedSection = .terminal
        handleSectionEntry(.terminal)
        setStatusMessage(L10n.string("Opening %@ in Terminal…", session.resolvedTitle))
    }

    private func operateOnKanbanTask(
        taskID: String,
        successMessage: String,
        failureMessage: String,
        operation: (ConnectionProfile, String) async throws -> Void
    ) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnKanbanTask else { return }

        let boardSlug = selectedKanbanBoardSlug
        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskID
        kanbanError = nil

        do {
            try await operation(profile, boardSlug)
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return }
            await reloadKanbanAfterOperation(taskID: taskID, boardSlug: boardSlug)
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            setStatusMessage(L10n.string(successMessage))
        } catch {
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string(failureMessage))
        }
    }

    private func reloadKanbanAfterOperation(taskID: String, boardSlug: String) async {
        await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
        guard selectedKanbanBoardSlug == boardSlug else { return }
        if kanbanBoard?.tasks.contains(where: { $0.id == taskID }) == true {
            selectedKanbanTaskID = taskID
            await loadKanbanTaskDetail(taskID: taskID)
        }
    }

    private func handleSectionEntry(_ section: AppSection) {
        switch section {
        case .overview:
            Task { await refreshOverview() }
        case .plugins:
            break
        case .files:
            Task { await ensureInitialFileLoads() }
        case .sessions:
            Task { await loadSessions(reset: true) }
        case .workflows:
            Task {
                loadWorkflows(reset: true)
                await loadSkills(reset: false)
                loadWorkflows(reset: true)
            }
        case .cronjobs:
            Task { await loadCronJobs() }
        case .kanban:
            Task { await loadKanbanBoard() }
        case .usage:
            Task { await loadUsage(forceRefresh: true) }
            Task { await loadAnalytics(forceRefresh: true) }
            Task { await loadModelsAnalytics(forceRefresh: true) }
        case .skills:
            Task { await loadSkills(reset: true) }
        case .terminal:
            ensureTerminalSession()
        case .connections:
            break
        case .analytics:
            Task { await loadDashboardOverview() }
        case .jobs:
            Task { await loadDashboardCronJobs() }
        case .mcp:
            Task { await loadMCPServers() }
        case .avatar, .youtubePipeline, .physicsSim, .secondBrain, .models, .config, .logs, .keys, .profiles, .docs, .chat, .memory, .soul, .tools, .office:
            break
        }
    }

    @discardableResult
    private func checkForUpdates(presentsCurrentResult: Bool) async -> Bool {
        guard !isCheckingForUpdates else { return false }

        isCheckingForUpdates = true
        if presentsCurrentResult {
            setStatusMessage(L10n.string("Checking for ARES updates…"))
        }

        do {
            let update = try await updateCheckService.checkForUpdate()
            isCheckingForUpdates = false

            if let update {
                availableUpdate = update
                setStatusMessage(L10n.string("ARES update available: %@", update.latestVersion))
            } else if presentsCurrentResult {
                activeAlert = AppAlert(
                    title: L10n.string("ARES is up to date"),
                    message: L10n.string(
                        "You are running ARES %@, which matches the latest ARES release.",
                        UpdateCheckService.bundleShortVersion()
                    )
                )
                setStatusMessage(nil)
            }
            return true
        } catch {
            isCheckingForUpdates = false
            if presentsCurrentResult {
                activeAlert = AppAlert(
                    title: L10n.string("Unable to check for updates"),
                    message: error.localizedDescription
                )
                setStatusMessage(nil)
            }
            return false
        }
    }

    private func shouldRunAutomaticUpdateCheck(now: Date = Date()) -> Bool {
        guard let lastAutomaticUpdateCheckAt = connectionStore.lastAutomaticUpdateCheckAt else {
            return true
        }

        return now.timeIntervalSince(lastAutomaticUpdateCheckAt) >= automaticUpdateCheckInterval
    }

    private func ensureInitialFileLoads() async {
        await loadSelectedWorkspaceFile()
    }

    private func document(for reference: WorkspaceFileReference) -> FileEditorDocument {
        var document = workspaceFileDocuments[reference.id] ??
            FileEditorDocument(fileID: reference.id, title: reference.title, remotePath: reference.remotePath)
        document.title = reference.title
        document.remotePath = reference.remotePath
        return document
    }

    private func resolvedRemotePath(for trackedFile: RemoteTrackedFile, connection: ConnectionProfile) -> String {
        trackedFile.resolvedRemotePath(using: overview?.paths) ?? connection.remotePath(for: trackedFile)
    }

    private func isActiveWorkspace(_ profile: ConnectionProfile) -> Bool {
        activeConnection?.workspaceScopeFingerprint == profile.workspaceScopeFingerprint
    }

    private func setDocument(_ document: FileEditorDocument) {
        workspaceFileDocuments[document.fileID] = document
    }

    private func reloadWorkspaceScope(section: AppSection, statusMessage: String) async {
        resetWorkspaceStateForConnectionChange(closeTerminalTabs: false)
        selectedSection = section
        setStatusMessage(statusMessage)
        if let profile = activeConnection {
            await startTunnelIfNeeded(for: profile)
        }
        await prepareWorkspaceForActiveConnection()
        await reloadSectionAfterScopeChange(section)
    }

    private func reloadSectionAfterScopeChange(_ section: AppSection) async {
        switch section {
        case .connections, .overview:
            break
        case .files:
            await ensureInitialFileLoads()
        case .sessions:
            await loadSessions(reset: true)
        case .workflows:
            loadWorkflows(reset: true)
            await loadSkills(reset: false)
            loadWorkflows(reset: true)
        case .cronjobs:
            await loadCronJobs()
        case .kanban:
            await loadKanbanBoard()
        case .usage:
            await loadUsage(forceRefresh: true)
            await loadAnalytics(forceRefresh: true)
            await loadModelsAnalytics(forceRefresh: true)
        case .skills:
            await loadSkills(reset: true)
        case .terminal:
            ensureTerminalSession()
        case .jobs:
            await loadDashboardCronJobs()
        case .mcp:
            await loadMCPServers()
        case .analytics:
            break
        case .avatar, .secondBrain, .youtubePipeline, .physicsSim, .models, .config, .logs, .keys, .profiles, .plugins, .docs, .chat, .memory, .soul, .tools, .office:
            break
        }
    }

    private func clearSessionMessages() {
        guard !sessionMessages.isEmpty || !sessionMessageDisplays.isEmpty else { return }
        sessionMessages = []
        sessionMessageDisplays = []
        sessionMessageSignature = SessionMessageSignature(messages: [])
    }

    private func sessionStatusMessage(forConversationError message: String, fallback: String) -> String {
        if message.contains(approvalNeededMessage) {
            return L10n.string("Approval needed")
        }
        return L10n.string(fallback)
    }

    private func setSessionMessages(
        _ messages: [SessionMessage],
        for profile: ConnectionProfile? = nil,
        sessionID: String? = nil
    ) async {
        let signature = await Task.detached(priority: .userInitiated) {
            SessionMessageSignature(messages: messages)
        }.value

        if let profile {
            guard isActiveWorkspace(profile) else { return }
        }
        if let sessionID {
            guard selectedSessionID == sessionID else { return }
        }
        guard signature != sessionMessageSignature else { return }

        let displays = await Task.detached(priority: .userInitiated) {
            Self.makeSessionMessageDisplays(from: messages)
        }.value

        if let profile {
            guard isActiveWorkspace(profile) else { return }
        }
        if let sessionID {
            guard selectedSessionID == sessionID else { return }
        }
        applySessionMessages(messages, displays: displays, signature: signature)
    }

    private func applySessionMessages(
        _ messages: [SessionMessage],
        displays: [SessionMessageDisplay],
        signature: SessionMessageSignature
    ) {
        guard signature != sessionMessageSignature else { return }
        sessionMessages = messages
        sessionMessageDisplays = displays
        sessionMessageSignature = signature
    }

    nonisolated private static func makeSessionMessageDisplays(
        from messages: [SessionMessage]
    ) -> [SessionMessageDisplay] {
        messages.map(SessionMessageDisplay.init)
    }

    private func startSessionTranscriptPolling(sessionID: String, connection: ConnectionProfile) {
        stopSessionTranscriptPolling()
        let workspaceScopeFingerprint = connection.workspaceScopeFingerprint

        sessionTranscriptPollingTask = Task { [sessionBrowserService] in
            while !Task.isCancelled {
                do {
                    let messages = try await sessionBrowserService.loadTranscript(
                        connection: connection,
                        sessionID: sessionID
                    )

                    let signature = await Task.detached(priority: .utility) {
                        SessionMessageSignature(messages: messages)
                    }.value

                    let shouldBuildDisplays = await MainActor.run { [weak self] in
                        guard let self,
                              self.activeConnection?.workspaceScopeFingerprint == workspaceScopeFingerprint,
                              self.isSendingSessionMessage,
                              self.selectedSessionID == sessionID else {
                            return false
                        }
                        return signature != self.sessionMessageSignature
                    }

                    guard shouldBuildDisplays else {
                        try? await Task.sleep(for: .seconds(2))
                        continue
                    }

                    let displays = await Task.detached(priority: .utility) {
                        Self.makeSessionMessageDisplays(from: messages)
                    }.value

                    await MainActor.run { [weak self] in
                        guard let self,
                              self.activeConnection?.workspaceScopeFingerprint == workspaceScopeFingerprint,
                              self.isSendingSessionMessage,
                              self.selectedSessionID == sessionID else {
                            return
                        }
                        self.applySessionMessages(messages, displays: displays, signature: signature)
                    }
                } catch {
                    // Keep polling best-effort; a transient SSH/store read failure
                    // should not end the in-flight chat turn.
                }

                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func stopSessionTranscriptPolling() {
        sessionTranscriptPollingTask?.cancel()
        sessionTranscriptPollingTask = nil
    }

    private func loadUsageProfileBreakdown(
        using connection: ConnectionProfile,
        activeSummary: UsageSummary,
        discoveredProfiles: [RemoteHermesProfile]
    ) async -> UsageProfileBreakdown {
        var slices: [UsageProfileSlice] = []
        let activeProfileName = connection.resolvedHermesProfileName

        for discoveredProfile in discoveredProfiles {
            if discoveredProfile.name == activeProfileName {
                slices.append(
                    usageProfileSlice(
                        for: discoveredProfile,
                        summary: activeSummary,
                        activeProfileName: activeProfileName
                    )
                )
                continue
            }

            let scopedConnection = connection.applyingHermesProfile(named: discoveredProfile.name)

            do {
                let summary = try await usageBrowserService.loadUsage(
                    connection: scopedConnection,
                    hintedSessionStore: nil
                )

                slices.append(
                    usageProfileSlice(
                        for: discoveredProfile,
                        summary: summary,
                        activeProfileName: activeProfileName
                    )
                )
            } catch {
                slices.append(
                    UsageProfileSlice(
                        profileName: discoveredProfile.name,
                        hermesHomePath: discoveredProfile.path,
                        state: .unavailable,
                        sessionCount: 0,
                        inputTokens: 0,
                        outputTokens: 0,
                        cacheReadTokens: 0,
                        cacheWriteTokens: 0,
                        reasoningTokens: 0,
                        databasePath: nil,
                        message: error.localizedDescription,
                        isActiveProfile: discoveredProfile.name == activeProfileName
                    )
                )
            }
        }

        return UsageProfileBreakdown(profiles: slices)
    }

    private func usageProfileSlice(
        for discoveredProfile: RemoteHermesProfile,
        summary: UsageSummary,
        activeProfileName: String
    ) -> UsageProfileSlice {
        UsageProfileSlice(
            profileName: discoveredProfile.name,
            hermesHomePath: discoveredProfile.path,
            state: summary.state,
            sessionCount: summary.sessionCount,
            inputTokens: summary.inputTokens,
            outputTokens: summary.outputTokens,
            cacheReadTokens: summary.cacheReadTokens,
            cacheWriteTokens: summary.cacheWriteTokens,
            reasoningTokens: summary.reasoningTokens,
            databasePath: summary.databasePath,
            message: summary.message,
            isActiveProfile: discoveredProfile.name == activeProfileName
        )
    }

    private func prepareWorkspaceForActiveConnection() async {
        guard let profile = activeConnection else { return }
        await refreshOverview()
        guard isActiveWorkspace(profile) else { return }

        guard overviewError == nil else {
            isRefreshingOverview = false
            sessions = []
            clearSessionMessages()
            sessionsError = nil
            isLoadingSessions = false
            isRefreshingSessions = false
            pendingSessionReloadQuery = nil
            isSendingSessionMessage = false
            sessionConversationError = nil
            pendingSessionTurn = nil
            stopSessionTranscriptPolling()
            chatMessages = []
            isStreamingChat = false
            chatError = nil
            chatSessionID = nil
            workflows = []
            selectedWorkflowID = nil
            usageSummary = nil
            usageProfileBreakdown = nil
            usageError = nil
            isLoadingUsage = false
            isRefreshingUsage = false
            analyticsResponse = nil
            modelsAnalyticsResponse = nil
            isLoadingAnalytics = false
            isRefreshingAnalytics = false
            analyticsError = nil
            analyticsDays = 30
            skills = []
            selectedSkillID = nil
            selectedSkillDetail = nil
            skillsError = nil
            isLoadingSkills = false
            isRefreshingSkills = false
            isLoadingSkillDetail = false
            isSavingSkillDraft = false
            cronJobs = []
            selectedCronJobID = nil
            cronJobsError = nil
            isLoadingCronJobs = false
            isRefreshingCronJobs = false
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            isSavingCronJobDraft = false
            kanbanBoards = []
            selectedKanbanBoardSlug = KanbanProject.defaultSlug
            remoteCurrentKanbanBoardSlug = nil
            supportsKanbanBoardManagement = false
            kanbanBoard = nil
            selectedKanbanTaskID = nil
            selectedKanbanTaskDetail = nil
            kanbanError = nil
            isLoadingKanbanBoards = false
            isLoadingKanbanBoard = false
            isRefreshingKanbanBoard = false
            isLoadingKanbanTaskDetail = false
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            isSavingKanbanTaskDraft = false
            isSavingKanbanBoardDraft = false
            isOperatingOnKanbanBoard = false
            isDispatchingKanban = false
            includeArchivedKanbanTasks = false
            dashboardCronJobs = []
            dashboardCronJobsError = nil
            isLoadingDashboardCronJobs = false
            mcpServers = []
            mcpMarketplaceItems = []
            mcpError = nil
            isLoadingMCP = false
            resetDocuments()
            return
        }

        await ensureInitialFileLoads()
        await loadSessions(reset: true)
        startApprovalPolling()
        startContextPolling()
    }

    private func resetWorkspaceStateForConnectionChange(closeTerminalTabs: Bool = true) {
        stopApprovalPolling()
        stopContextPolling()
        tunnelService.stop()
        isBusy = false
        connectionTestRequestID = nil
        overview = nil
        overviewError = nil
        isRefreshingOverview = false
        sessions = []
        clearSessionMessages()
        sessionsError = nil
        isLoadingSessions = false
        isRefreshingSessions = false
        isDeletingSession = false
        isSendingSessionMessage = false
        sessionConversationError = nil
        pendingSessionTurn = nil
        stopSessionTranscriptPolling()
        chatMessages = []
        isStreamingChat = false
        chatError = nil
        chatSessionID = nil
        hasMoreSessions = false
        totalSessionsCount = 0
        selectedSessionID = nil
        isNewSessionComposerActive = false
        sessionOffset = 0
        pendingSessionReloadQuery = nil
        pendingSectionEntryAction = nil
        sessionSearchQuery = ""
        workflows = []
        selectedWorkflowID = nil
        usageSummary = nil
        usageProfileBreakdown = nil
        usageError = nil
        isLoadingUsage = false
        isRefreshingUsage = false
        analyticsResponse = nil
        modelsAnalyticsResponse = nil
        isLoadingAnalytics = false
        isRefreshingAnalytics = false
        analyticsError = nil
        analyticsDays = 30
        skills = []
        selectedSkillID = nil
        selectedSkillDetail = nil
        skillsError = nil
        isLoadingSkills = false
        isRefreshingSkills = false
        isLoadingSkillDetail = false
        isSavingSkillDraft = false
        cronJobs = []
        selectedCronJobID = nil
        cronJobsError = nil
        isLoadingCronJobs = false
        isRefreshingCronJobs = false
        isOperatingOnCronJob = false
        operatingCronJobID = nil
        isSavingCronJobDraft = false
        kanbanBoards = []
        selectedKanbanBoardSlug = KanbanProject.defaultSlug
        remoteCurrentKanbanBoardSlug = nil
        supportsKanbanBoardManagement = false
        kanbanBoard = nil
        selectedKanbanTaskID = nil
        selectedKanbanTaskDetail = nil
        kanbanError = nil
        isLoadingKanbanBoards = false
        isLoadingKanbanBoard = false
        isRefreshingKanbanBoard = false
        isLoadingKanbanTaskDetail = false
        isOperatingOnKanbanTask = false
        operatingKanbanTaskID = nil
        isSavingKanbanTaskDraft = false
        isSavingKanbanBoardDraft = false
        isOperatingOnKanbanBoard = false
        isDispatchingKanban = false
        includeArchivedKanbanTasks = false
        dashboardCronJobs = []
        dashboardCronJobsError = nil
        isLoadingDashboardCronJobs = false
        mcpServers = []
        mcpMarketplaceItems = []
        mcpError = nil
        isLoadingMCP = false
        resetDocuments()
        if closeTerminalTabs {
            terminalWorkspace.closeAllTabs()
        }
    }

    private func resetDocuments() {
        workspaceFileDocuments = [:]
        workspaceFileBrowserListing = nil
        workspaceFileBrowserError = nil
        isLoadingWorkspaceFileBrowser = false
        selectedWorkspaceFileID = RemoteTrackedFile.memory.workspaceFileID
    }

    func setStatusMessage(_ message: String?) {
        statusTask?.cancel()
        statusMessage = message

        guard let message else { return }

        statusTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.statusMessage == message else { return }
                self.statusMessage = nil
            }
        }
    }

    // MARK: - Soul

    func loadSoul() async {
        guard let connection = activeConnection else { return }
        soulError = nil
        do {
            let content = try await soulService.fetchSoul(connection: connection)
            guard isActiveWorkspace(connection) else { return }
            soulContent = content
        } catch {
            guard isActiveWorkspace(connection) else { return }
            soulError = error.localizedDescription
        }
    }

    func saveSoul(_ content: String) async {
        guard let connection = activeConnection else { return }
        isSavingSoul = true
        soulError = nil
        do {
            try await soulService.saveSoul(content, connection: connection)
            guard isActiveWorkspace(connection) else { return }
            soulContent = content
            isSavingSoul = false
        } catch {
            guard isActiveWorkspace(connection) else { return }
            isSavingSoul = false
            soulError = error.localizedDescription
        }
    }

    // MARK: - Memory

    func loadMemory() async {
        isLoadingMemory = true
        memoryError = nil
        do {
            let response = try await dashboardAPIService.fetchMemory()
            memoryEntries = response.entries
            isLoadingMemory = false
        } catch {
            isLoadingMemory = false
            memoryError = error.localizedDescription
        }
    }

    func deleteMemoryEntry(id: String) async {
        do {
            try await dashboardAPIService.deleteMemoryEntry(id: id)
            memoryEntries.removeAll { $0.id == id }
        } catch {
            memoryError = error.localizedDescription
        }
    }

    func updateMemoryEntry(id: String, content: String) async {
        do {
            try await dashboardAPIService.updateMemoryEntry(id: id, content: content)
            if let idx = memoryEntries.firstIndex(where: { $0.id == id }) {
                let old = memoryEntries[idx]
                memoryEntries[idx] = MemoryEntry(
                    id: old.id,
                    content: content,
                    createdAt: old.createdAt,
                    source: old.source
                )
            }
        } catch {
            memoryError = error.localizedDescription
        }
    }

    // MARK: - Tools

    func loadTools() async {
        isLoadingTools = true
        toolsError = nil
        do {
            let response = try await dashboardAPIService.fetchTools()
            tools = response.tools
            isLoadingTools = false
        } catch {
            isLoadingTools = false
            toolsError = error.localizedDescription
        }
    }

    func setToolEnabled(name: String, enabled: Bool) async {
        do {
            try await dashboardAPIService.setToolEnabled(name: name, enabled: enabled)
            if let idx = tools.firstIndex(where: { $0.name == name }) {
                tools[idx].enabled = enabled
            }
        } catch {
            toolsError = error.localizedDescription
        }
    }

    // MARK: - Tool Approvals

    private func startApprovalPolling() {
        approvalPollingTask?.cancel()
        approvalPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self, self.dashboardAPIAvailable {
                    await self.pollApprovals()
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func stopApprovalPolling() {
        approvalPollingTask?.cancel()
        approvalPollingTask = nil
        pendingApprovals = []
    }

    func pollApprovals() async {
        guard dashboardAPIAvailable else { return }
        do {
            let approvals = try await dashboardAPIService.fetchPendingApprovals()
            pendingApprovals = approvals
        } catch {
            // Silently ignore polling errors — the approval UI will just stay hidden
        }
    }

    func approveToolCall(_ approval: ToolApprovalRequest) async {
        do {
            try await dashboardAPIService.approveToolCall(id: approval.id)
            pendingApprovals.removeAll { $0.id == approval.id }
        } catch {
            // Re-poll to get fresh state on failure
            await pollApprovals()
        }
    }

    func denyToolCall(_ approval: ToolApprovalRequest) async {
        do {
            try await dashboardAPIService.denyToolCall(id: approval.id)
            pendingApprovals.removeAll { $0.id == approval.id }
        } catch {
            // Re-poll to get fresh state on failure
            await pollApprovals()
        }
    }

    // MARK: - Dashboard Analytics (Feature 1)

    func loadDashboardOverview() async {
        guard dashboardAPIAvailable else { return }
        isLoadingDashboard = true
        do {
            let overview = try await dashboardAPIService.fetchDashboardOverview(period: dashboardPeriod)
            dashboardOverview = overview
        } catch {
            // silently ignore — view shows ContentUnavailableView when data is nil
        }
        isLoadingDashboard = false
    }

    // MARK: - Usage Meter / Session Context (Feature 2)

    func startContextPolling() {
        guard dashboardAPIAvailable else { return }
        contextPollingTask?.cancel()
        firedContextThresholds = []
        contextPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollSessionContext()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func stopContextPolling() {
        contextPollingTask?.cancel()
        contextPollingTask = nil
    }

    private func pollSessionContext() async {
        guard dashboardAPIAvailable else { return }
        do {
            let status = try await dashboardAPIService.fetchSessionStatus()
            sessionContextUsed = status.contextUsed
            sessionContextLimit = max(status.contextLimit, 1)
            sessionDailyCost = status.dailyCost

            let pct = Int(Double(sessionContextUsed) / Double(sessionContextLimit) * 100)
            for threshold in [50, 75, 90] {
                if pct >= threshold && !firedContextThresholds.contains(threshold) {
                    firedContextThresholds.insert(threshold)
                    contextAlertThreshold = threshold
                    break
                }
            }
        } catch {
            // silently ignore polling errors
        }
    }

    func dismissContextAlert() {
        contextAlertThreshold = nil
    }
}

private struct SessionMessageSignature: Equatable, Sendable {
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

private struct ConnectionTestRequest: Encodable {}

private struct ConnectionTestResponse: Decodable {
    let ok: Bool
    let remoteHome: String
    let pythonExecutable: String?

    enum CodingKeys: String, CodingKey {
        case ok
        case remoteHome = "remote_home"
        case pythonExecutable = "python_executable"
    }
}
