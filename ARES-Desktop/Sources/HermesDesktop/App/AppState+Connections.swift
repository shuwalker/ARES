import Foundation

extension AppState {
    // MARK: - Connections

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

    func startTunnelIfNeeded(for profile: ConnectionProfile) async {
        // Direct HTTP path — no SSH tunnel needed.
        if profile.transportMode == .directHTTP {
            tunnelService.stop()
            dashboardAPIService.baseURL = profile.directHTTPBaseURL
            do {
                _ = try await dashboardAPIService.fetchStatus()
            } catch {
                // Connectivity check failed; status message will surface this.
                setStatusMessage(L10n.string("Direct HTTP connection to %@ failed: %@", profile.label, error.localizedDescription))
            }
            return
        }

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

    func deleteConnection(_ profile: ConnectionProfile) {
        connectionStore.delete(profile)
        terminalWorkspace.closeTabs(forConnectionID: profile.id)
        if activeConnectionID == profile.id {
            activeConnectionID = nil
            resetWorkspaceStateForConnectionChange(closeTerminalTabs: false)
            selectedSection = .connections
        }
    }

    // MARK: - Workspace reset

    func resetWorkspaceStateForConnectionChange(closeTerminalTabs: Bool = true) {
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

    func resetDocuments() {
        workspaceFileDocuments = [:]
        workspaceFileBrowserListing = nil
        workspaceFileBrowserError = nil
        isLoadingWorkspaceFileBrowser = false
        selectedWorkspaceFileID = RemoteTrackedFile.memory.workspaceFileID
    }

    // MARK: - Status

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

    // MARK: - Workspace helpers

    func isActiveWorkspace(_ profile: ConnectionProfile) -> Bool {
        activeConnection?.workspaceScopeFingerprint == profile.workspaceScopeFingerprint
    }
}
