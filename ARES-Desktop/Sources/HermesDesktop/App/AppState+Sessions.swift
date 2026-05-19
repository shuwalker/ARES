import Foundation
import SwiftUI

extension AppState {
    // MARK: - Sessions

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

    func refreshSessions(query: String? = nil) async {
        guard !isLoadingSessions, !isRefreshingSessions else { return }
        isRefreshingSessions = true
        await loadSessions(reset: true, query: query)
        isRefreshingSessions = false
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
                await autoTitleSessionIfNeeded(
                    sessionID: createdSessionID,
                    firstUserPrompt: trimmedPrompt
                )
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

    // MARK: - Session internal helpers

    func startSessionTranscriptPolling(sessionID: String, connection: ConnectionProfile) {
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

    func stopSessionTranscriptPolling() {
        sessionTranscriptPollingTask?.cancel()
        sessionTranscriptPollingTask = nil
    }

    func clearSessionMessages() {
        guard !sessionMessages.isEmpty || !sessionMessageDisplays.isEmpty else { return }
        sessionMessages = []
        sessionMessageDisplays = []
        sessionMessageSignature = SessionMessageSignature(messages: [])
    }

    func sessionStatusMessage(forConversationError message: String, fallback: String) -> String {
        if message.contains(approvalNeededMessage) {
            return L10n.string("Approval needed")
        }
        return L10n.string(fallback)
    }

    func setSessionMessages(
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

    func applySessionMessages(
        _ messages: [SessionMessage],
        displays: [SessionMessageDisplay],
        signature: SessionMessageSignature
    ) {
        guard signature != sessionMessageSignature else { return }
        sessionMessages = messages
        sessionMessageDisplays = displays
        sessionMessageSignature = signature
    }

    nonisolated static func makeSessionMessageDisplays(
        from messages: [SessionMessage]
    ) -> [SessionMessageDisplay] {
        messages.map(SessionMessageDisplay.init)
    }

    private func clearSessionScrollOffset(for sessionID: String) {
        sessionScrollOffsets.removeValue(forKey: sessionID)
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

    // MARK: - Auto-title

    /// After a new session's first exchange, if the session has no meaningful title,
    /// derive one from the first user prompt (truncated to 60 characters) and persist
    /// it via the Dashboard API. The local session list is also refreshed so the
    /// sidebar reflects the new title immediately.
    func autoTitleSessionIfNeeded(sessionID: String, firstUserPrompt: String) async {
        let existingSummary = sessionSummary(for: sessionID)
        let existingTitle = existingSummary?.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isPlaceholder = existingTitle.isEmpty
            || existingTitle.lowercased() == "new session"
            || existingTitle.lowercased() == "untitled"

        guard isPlaceholder else { return }

        let maxTitleLength = 60
        let trimmed = firstUserPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let newTitle: String
        if trimmed.count > maxTitleLength {
            newTitle = String(trimmed.prefix(maxTitleLength))
        } else {
            newTitle = trimmed
        }

        // Update the local model immediately for instant sidebar feedback.
        if let index = sessions.firstIndex(where: { $0.id == sessionID }) {
            let old = sessions[index]
            sessions[index] = SessionSummary(
                id: old.id,
                title: newTitle,
                model: old.model,
                startedAt: old.startedAt,
                lastActive: old.lastActive,
                messageCount: old.messageCount,
                preview: old.preview,
                searchMatch: old.searchMatch,
                source: old.source,
                status: old.status
            )
        }

        // Persist via Dashboard API on a best-effort basis.
        do {
            try await dashboardAPIService.renameSession(id: sessionID, title: newTitle)
        } catch {
            // Silently swallow — the title update is cosmetic and the endpoint may
            // not be present on all Hermes versions.
        }
    }
}
