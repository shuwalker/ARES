import Foundation

extension AppState {
    // MARK: - Navigation

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
        case .swarm:
            await loadSwarm()
        case .conductor:
            break
        case .operations:
            await loadOperations()
        case .crewStatus:
            await loadCrewStatus()
        case .secondBrain, .youtubePipeline, .physicsSim, .docs, .chat, .memory, .soul, .tools, .office:
            break
        case .connections, .files, .terminal, .avatar, .models, .config, .logs, .keys, .profiles, .plugins:
            break
        }
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

    // MARK: - Update checks

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

    @discardableResult
    func checkForUpdates(presentsCurrentResult: Bool) async -> Bool {
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

    func shouldRunAutomaticUpdateCheck(now: Date = Date()) -> Bool {
        guard let lastAutomaticUpdateCheckAt = connectionStore.lastAutomaticUpdateCheckAt else {
            return true
        }

        return now.timeIntervalSince(lastAutomaticUpdateCheckAt) >= automaticUpdateCheckInterval
    }

    // MARK: - Section entry

    func handleSectionEntry(_ section: AppSection) {
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
        case .swarm:
            Task { await loadSwarm() }
        case .conductor:
            break
        case .operations:
            Task { await loadOperations() }
        case .crewStatus:
            Task { await loadCrewStatus() }
        case .avatar, .youtubePipeline, .physicsSim, .secondBrain, .models, .config, .logs, .keys, .profiles, .docs, .chat, .memory, .soul, .tools, .office:
            break
        }
    }

    // MARK: - Misc computed refresh helpers

    func refreshKanbanBoard(includeArchived: Bool? = nil) async {
        guard !isLoadingKanbanBoard, !isRefreshingKanbanBoard else { return }
        isRefreshingKanbanBoard = true
        await loadKanbanBoards()
        await loadKanbanBoard(includeArchived: includeArchived)
        isRefreshingKanbanBoard = false
    }

    func refreshCronJobs() async {
        guard !isLoadingCronJobs, !isRefreshingCronJobs else { return }
        isRefreshingCronJobs = true
        await loadCronJobs()
        isRefreshingCronJobs = false
    }
}
