import Foundation

extension AppState {
    // MARK: - Overview

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

    func prepareWorkspaceForActiveConnection() async {
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

    func reloadWorkspaceScope(section: AppSection, statusMessage: String) async {
        resetWorkspaceStateForConnectionChange(closeTerminalTabs: false)
        selectedSection = section
        setStatusMessage(statusMessage)
        if let profile = activeConnection {
            await startTunnelIfNeeded(for: profile)
        }
        await prepareWorkspaceForActiveConnection()
        await reloadSectionAfterScopeChange(section)
    }

    func reloadSectionAfterScopeChange(_ section: AppSection) async {
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
        case .swarm:
            await loadSwarm()
        case .conductor:
            break
        case .operations:
            await loadOperations()
        case .crewStatus:
            await loadCrewStatus()
        case .avatar, .secondBrain, .youtubePipeline, .physicsSim, .models, .config, .logs, .keys, .profiles, .plugins, .docs, .chat, .memory, .soul, .tools, .office:
            break
        }
    }
}
