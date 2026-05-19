import AppKit
import SwiftUI

struct SessionsView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var splitLayout: HermesSplitLayout
    let isActive: Bool
    @State private var searchText = ""
    @State private var showToolActivity = false
    @StateObject private var toolActivityModel = LiveToolActivityModel()

    var body: some View {
        HermesCollapsibleHSplitView(layout: $splitLayout, detailMinWidth: 420) {
            VStack(alignment: .leading, spacing: 18) {
                HermesPageHeader(
                    title: "Sessions",
                    subtitle: "Browse the recent Hermes conversations discovered on the active host."
                ) {
                    HermesExpandableSearchField(
                        text: $searchText,
                        prompt: L10n.string("Search sessions"),
                        expandedWidth: 220,
                        focusRequestID: appState.searchFocusRequestID
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }

                sessionsToolbar
                sessionsContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
        } detail: {
            if showToolActivity {
                // Split detail: chat + tool activity panel
                HSplitView {
                    SessionDetailView(
                        session: selectedSession,
                        messages: appState.sessionMessageDisplays,
                        errorMessage: appState.sessionsError,
                        conversationError: appState.sessionConversationError,
                        isSendingMessage: appState.isSendingSessionMessage,
                        isDeletingSession: selectedSession.map { selectedSession in
                            appState.isDeletingSession && appState.selectedSessionID == selectedSession.id
                        } ?? false,
                        pendingTurn: appState.pendingSessionTurn,
                        isActive: isActive,
                        savedScrollOffset: selectedSession.flatMap { selectedSession in
                            appState.savedSessionScrollOffset(for: selectedSession.id)
                        },
                        onSaveScrollOffset: { sessionID, offset in
                            appState.saveSessionScrollOffset(offset, for: sessionID)
                        },
                        onResumeInTerminal: { session in
                            appState.resumeSessionInTerminal(session)
                        },
                        onDeleteSession: { session in
                            await appState.deleteSession(session)
                        },
                        onStartSession: { prompt, autoApproveCommands in
                            await appState.startNewSession(
                                with: prompt,
                                autoApproveCommands: autoApproveCommands
                            )
                        },
                        onSendMessage: { prompt, autoApproveCommands in
                            await appState.sendMessageToSelectedSession(
                                prompt,
                                autoApproveCommands: autoApproveCommands
                            )
                        }
                    )
                    .frame(minWidth: 320)

                    LiveToolActivityView(model: toolActivityModel)
                        .frame(minWidth: 220, idealWidth: 280, maxWidth: 400)
                }
            } else {
                SessionDetailView(
                    session: selectedSession,
                    messages: appState.sessionMessageDisplays,
                    errorMessage: appState.sessionsError,
                    conversationError: appState.sessionConversationError,
                    isSendingMessage: appState.isSendingSessionMessage,
                    isDeletingSession: selectedSession.map { selectedSession in
                        appState.isDeletingSession && appState.selectedSessionID == selectedSession.id
                    } ?? false,
                    pendingTurn: appState.pendingSessionTurn,
                    isActive: isActive,
                    savedScrollOffset: selectedSession.flatMap { selectedSession in
                        appState.savedSessionScrollOffset(for: selectedSession.id)
                    },
                    onSaveScrollOffset: { sessionID, offset in
                        appState.saveSessionScrollOffset(offset, for: sessionID)
                    },
                    onResumeInTerminal: { session in
                        appState.resumeSessionInTerminal(session)
                    },
                    onDeleteSession: { session in
                        await appState.deleteSession(session)
                    },
                    onStartSession: { prompt, autoApproveCommands in
                        await appState.startNewSession(
                            with: prompt,
                            autoApproveCommands: autoApproveCommands
                        )
                    },
                    onSendMessage: { prompt, autoApproveCommands in
                        await appState.sendMessageToSelectedSession(
                            prompt,
                            autoApproveCommands: autoApproveCommands
                        )
                    }
                )
                .hermesSplitDetailColumn(minWidth: 420, idealWidth: 520)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: sessionsLoadTaskID) {
            guard isActive else { return }
            if appState.sessions.isEmpty {
                await appState.loadSessions(reset: true)
            }
        }
        .task(id: searchTaskID) {
            guard isActive else { return }
            guard appState.activeConnectionID != nil else { return }

            let normalizedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard normalizedQuery != appState.sessionSearchQuery else { return }

            try? await Task.sleep(for: .milliseconds(280))
            guard !Task.isCancelled else { return }
            await appState.loadSessions(reset: true, query: searchText)
        }
    }

    private var sessionsLoadTaskID: String {
        "\(isActive):\(appState.activeConnectionID?.uuidString ?? "none")"
    }

    private var searchTaskID: String {
        "\(isActive):\(searchText)"
    }

    @ViewBuilder
    private var sessionsContent: some View {
        sessionsPanel
    }

    @ViewBuilder
    private var sessionsPanel: some View {
        if appState.isLoadingSessions && !hasVisibleSessions {
            HermesSurfacePanel {
                HermesLoadingState(
                    label: "Loading sessions…",
                    minHeight: 300
                )
            }
        } else if let error = appState.sessionsError, !hasVisibleSessions {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("Unable to load sessions"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else if !hasVisibleSessions && !appState.sessionSearchQuery.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("No matching sessions"),
                    systemImage: "magnifyingglass",
                    description: Text(L10n.string("Try searching by session name, ID, preview text, or message content."))
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else if !hasVisibleSessions {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("No sessions yet"),
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(L10n.string("No sessions yet. Start chatting to create your first session."))
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else {
            HermesSurfacePanel(
                title: panelTitle,
                subtitle: "Select a session to inspect its transcript, metadata and last activity."
            ) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if !visiblePinnedSessions.isEmpty {
                            SessionSectionHeader(
                                title: L10n.string(
                                    "Pinned Sessions (%@)",
                                    "\(visiblePinnedSessions.count)"
                                )
                            )

                            ForEach(visiblePinnedSessions) { session in
                                sessionRow(session)
                            }

                            if !visibleStoredSessions.isEmpty {
                                Divider()
                                    .padding(.vertical, 2)

                                SessionSectionHeader(
                                    title: L10n.string("All Sessions (%@)", "\(appState.totalSessionsCount)")
                                )
                            }
                        }

                        ForEach(visibleStoredSessions) { session in
                            sessionRow(session)
                        }

                        if appState.hasMoreSessions {
                            Button(L10n.string("Load More")) {
                                Task { await appState.loadSessions(reset: false) }
                            }
                            .buttonStyle(.bordered)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 6)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .overlay(alignment: .topTrailing) {
                if appState.isLoadingSessions && !appState.isRefreshingSessions && !appState.sessions.isEmpty {
                    HermesLoadingOverlay()
                        .padding(18)
                }
            }
        }
    }

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var shouldShowPinnedSessions: Bool {
        appState.sessionSearchQuery.isEmpty && trimmedSearchText.isEmpty
    }

    private var visiblePinnedSessions: [SessionSummary] {
        shouldShowPinnedSessions ? appState.pinnedSessionSummaries : []
    }

    private var visibleStoredSessions: [SessionSummary] {
        shouldShowPinnedSessions ? appState.unpinnedSessions : appState.sessions
    }

    private var hasVisibleSessions: Bool {
        !visiblePinnedSessions.isEmpty || !visibleStoredSessions.isEmpty
    }

    private func sessionRow(_ session: SessionSummary) -> some View {
        let isPinned = appState.isSessionPinned(session.id)

        return SessionCardRow(
            session: session,
            isSelected: session.id == appState.selectedSessionID,
            isPinned: isPinned,
            isSendingMessage: appState.isSendingSessionMessage,
            onTogglePin: {
                appState.toggleSessionPin(session)
            },
            onSendInline: { prompt in
                Task {
                    // Ensure the target session is selected before sending
                    if appState.selectedSessionID != session.id {
                        await appState.loadSessionDetail(sessionID: session.id)
                    }
                    _ = await appState.sendMessageToSelectedSession(prompt, autoApproveCommands: false)
                }
            }
        ) {
            Task {
                await appState.loadSessionDetail(sessionID: session.id)
            }
        }
        // Rows move between two LazyVStack sections when pinned. Include the pin state
        // in the row identity so the pin button subtree is rebuilt with the move.
        .id(SessionCardRowIdentity(sessionID: session.id, isPinned: isPinned))
    }

    private var sessionsToolbar: some View {
        HStack(spacing: 10) {
            HermesCreateActionButton("New Chat") {
                searchText = ""
                appState.prepareNewSessionComposer()
            }
            .disabled(appState.isSendingSessionMessage)

            Spacer()

            // Toggle live tool activity viewer
            Button {
                showToolActivity.toggle()
                if showToolActivity {
                    configureToolActivityModel()
                    toolActivityModel.connect()
                } else {
                    toolActivityModel.disconnect()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showToolActivity ? "wrench.and.screwdriver.fill" : "wrench.and.screwdriver")
                        .font(.caption.weight(.medium))
                    if !toolActivityModel.events.isEmpty {
                        Text("\(toolActivityModel.events.count)")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.accentColor))
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help(showToolActivity ? "Hide Tool Activity" : "Show Tool Activity")
            .tint(showToolActivity ? .accentColor : .secondary)
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func configureToolActivityModel() {
        // Read gateway config from the active connection
        if let connection = appState.activeConnection {
            if connection.sshHost.isEmpty {
                // Local connection — gateway is on this machine
                toolActivityModel.gatewayHost = "localhost"
                toolActivityModel.gatewayPort = 9119
            } else {
                // Remote connection — gateway is on the SSH host
                toolActivityModel.gatewayHost = connection.sshHost
                toolActivityModel.gatewayPort = 9119
            }
            // Fetch token asynchronously then connect
            Task {
                toolActivityModel.sessionToken = await fetchGatewayToken()
            }
        }
    }

    @MainActor
    private func fetchGatewayToken() async -> String? {
        // Fetch the session token from the gateway HTML page
        let urlString = "http://\(toolActivityModel.gatewayHost):\(toolActivityModel.gatewayPort)/"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let html = String(data: data, encoding: .utf8) else { return nil }
            // Extract __HERMES_SESSION_TOKEN__="<token>"
            if let range = html.range(of: #"__HERMES_SESSION_TOKEN__="([^"]+)""#, options: .regularExpression) {
                let match = String(html[range])
                if let quoteRange = match.range(of: #"="([^"]+)""#, options: .regularExpression) {
                    let value = String(match[quoteRange])
                    return value.replacingOccurrences(of: "=\"", with: "").replacingOccurrences(of: "\"", with: "")
                }
            }
        } catch {
            // Silently fail — token will be nil, WS connects without it
        }
        return nil
    }

    private var panelTitle: String {
        if appState.sessionSearchQuery.isEmpty {
            return L10n.string("Sessions Library (%@)", "\(appState.totalSessionsCount)")
        }

        return L10n.string("Matching Sessions (%@)", "\(appState.totalSessionsCount)")
    }

    private var selectedSession: SessionSummary? {
        guard let selectedSessionID = appState.selectedSessionID else { return nil }
        return appState.sessionSummary(for: selectedSessionID)
    }
}

private struct SessionCardRowIdentity: Hashable {
    let sessionID: String
    let isPinned: Bool
}

private struct SessionSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 2)
    }
}

private struct SessionCardRow: View {
    let session: SessionSummary
    let isSelected: Bool
    let isPinned: Bool
    let isSendingMessage: Bool
    let onTogglePin: () -> Void
    let onSendInline: (String) -> Void
    let onSelect: () -> Void

    @State private var isHovering = false
    @State private var isPulsing = false
    @State private var isComposerExpanded = false
    @State private var inlineDraft = ""
    @FocusState private var isComposerFocused: Bool

    private var trimmedDraft: String {
        inlineDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onSelect) {
                content
                    .padding(.trailing, (isSelected || isHovering) ? 64 : 34)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                            .fill(isSelected ? HermesTheme.selectedFill : HermesTheme.rowFill)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                            .strokeBorder(isSelected ? HermesTheme.selectedStroke : HermesTheme.subtleStroke, lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)

            if isComposerExpanded {
                inlineComposer
                    .padding(.top, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isComposerExpanded)
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 6) {
                if isPinned || isSelected || isHovering {
                    pinButton
                        .transition(.opacity)
                }

                if isSelected || isHovering {
                    inlineComposerToggle
                        .transition(.opacity)
                }
            }
            .padding(.top, 10)
            .padding(.trailing, 14)
        }
        .onHover { isHovering = $0 }
        .contextMenu {
            Button(pinHelpText, action: onTogglePin)

            Button(L10n.string("Copy Session ID")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.id, forType: .string)
            }
        }
    }

    private var inlineComposerToggle: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isComposerExpanded.toggle()
                if !isComposerExpanded {
                    inlineDraft = ""
                } else {
                    // Focus the text field when expanding
                    DispatchQueue.main.async {
                        isComposerFocused = true
                    }
                }
            }
        } label: {
            Image(systemName: isComposerExpanded ? "chevron.up" : "paperplane")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isComposerExpanded ? Color.accentColor : Color.secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isComposerExpanded ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(isComposerExpanded ? L10n.string("Close inline composer") : L10n.string("Send a message to this session"))
        .accessibilityLabel(isComposerExpanded ? L10n.string("Close inline composer") : L10n.string("Send a message to this session"))
    }

    private var inlineComposer: some View {
        HStack(spacing: 8) {
            TextField(L10n.string("Message…"), text: $inlineDraft)
                .textFieldStyle(.roundedBorder)
                .focused($isComposerFocused)
                .onSubmit {
                    submitInlineDraft()
                }
                .disabled(isSendingMessage)

            Button {
                submitInlineDraft()
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSendingMessage || trimmedDraft.isEmpty)
            .help(L10n.string("Send message (Return)"))
            .accessibilityLabel(L10n.string("Send"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .fill(HermesTheme.rowFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
        }
    }

    private func submitInlineDraft() {
        let prompt = trimmedDraft
        guard !isSendingMessage, !prompt.isEmpty else { return }
        inlineDraft = ""
        isComposerFocused = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            isComposerExpanded = false
        }
        onSendInline(prompt)
    }

    private var pinButton: some View {
        Button(action: onTogglePin) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isPinned ? Color.orange : Color.secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isPinned ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.08))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(pinHelpText)
        .accessibilityLabel(pinHelpText)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        statusDot

                        Text(session.resolvedTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)

                        if isPinned {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.orange)
                        }

                        sourceBadge
                    }

                    Text(session.id)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)

                if let count = session.messageCount {
                    HermesBadge(text: L10n.string("%@ messages", "\(count)"), tint: .secondary)
                }
            }

            if let searchMatch = session.searchMatch,
               let snippet = searchMatch.snippet,
               !snippet.isEmpty {
                searchMatchPreview(searchMatch, snippet: snippet)
            } else if let preview = session.preview, !preview.isEmpty {
                Text(preview)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    if let startedAt = session.startedAt?.dateValue {
                        metaLabel(L10n.string("Started %@", DateFormatters.relativeFormatter().localizedString(for: startedAt, relativeTo: .now)))
                    }

                    if let lastActive = session.lastActive?.dateValue {
                        metaLabel(L10n.string("Active %@", DateFormatters.relativeFormatter().localizedString(for: lastActive, relativeTo: .now)))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    if let startedAt = session.startedAt?.dateValue {
                        metaLabel(L10n.string("Started %@", DateFormatters.relativeFormatter().localizedString(for: startedAt, relativeTo: .now)))
                    }

                    if let lastActive = session.lastActive?.dateValue {
                        metaLabel(L10n.string("Active %@", DateFormatters.relativeFormatter().localizedString(for: lastActive, relativeTo: .now)))
                    }
                }
            }
        }
    }

    // MARK: - Status dot

    @ViewBuilder
    private var statusDot: some View {
        if session.isRunning {
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .scaleEffect(isPulsing ? 1.3 : 1.0)
                .animation(
                    .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                    value: isPulsing
                )
                .onAppear { isPulsing = true }
        } else {
            Circle()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 8, height: 8)
        }
    }

    // MARK: - Source badge

    @ViewBuilder
    private var sourceBadge: some View {
        if let source = session.source?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !source.isEmpty {
            let (label, tint) = Self.sourceAppearance(for: source)
            HermesBadge(text: label, tint: tint)
        }
    }

    private static func sourceAppearance(for source: String) -> (label: String, tint: Color) {
        switch source {
        case "cli":
            return ("CLI", .secondary)
        case "telegram":
            return ("TG", .blue)
        case "discord":
            return ("DC", .purple)
        case "cron":
            return ("CRON", .orange)
        case "api":
            return ("API", .green)
        default:
            return (source.uppercased().prefix(6).description, .secondary)
        }
    }

    private func searchMatchPreview(_ match: SessionSearchMatch, snippet: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "text.magnifyingglass")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                Text(searchMatchLabel(match))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }

            Text(snippet)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
    }

    private func searchMatchLabel(_ match: SessionSearchMatch) -> String {
        let countText = match.matchCount == 1
            ? L10n.string("1 match")
            : L10n.string("%@ matches", "\(match.matchCount)")

        guard let role = match.role else {
            return countText
        }

        return "\(role.displayTitle) - \(countText)"
    }

    private var pinHelpText: String {
        L10n.string(isPinned ? "Unpin session" : "Pin session")
    }

    private func metaLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}
