import ARESCore
import SwiftUI

// MARK: - CompanionView
//
// ARES Companion — the product. The three-pane layout:
//   [Avatar | Chat | History]
//
// Chat is a direct conversation with ARES (driven by CompanionChatService).
// References can be attached to a message from any installed tool session
// (Claude Code, Gemini, Odysseus, Hermes) via the "+" button.
// History pane shows recent ARES sessions; clicking one loads it read-only.

struct CompanionView: View {
    @EnvironmentObject private var appState: ARESAppState

    @State private var showStats: Bool = false
    @State private var showSourcePicker: Bool = false
    @State private var showModelPicker: Bool = false
    @State private var selectedReference: AttachedReference? = nil
    /// Tracks which bubble is in edit mode (nil = none).
    @State private var editingMessageId: ChatBubble.ID? = nil
    /// Holds the current edit text while editing a message.
    @State private var editText: String = ""

    // FocusState — required to receive first responder inside HSplitView
    // nested in NavigationSplitView (macOS focus routing bug workaround).
    private enum Field: Hashable { case chatInput }
    @FocusState private var focusedField: Field?

    var body: some View {
        GeometryReader { proxy in
            let isNarrow = proxy.size.width < 1200
            let showAvatar = proxy.size.width >= 900
            let showHistory = proxy.size.width >= 700
            HSplitView {
                if showAvatar {
                    // Left: ARES avatar + status
                    avatarPanel
                        .frame(minWidth: 220, idealWidth: isNarrow ? 240 : 320)
                        .background(ARESColors.background)
                }

                // Center: Chat
                chatPanel
                    .frame(minWidth: 380)

                if showHistory {
                    // Right: History
                    SessionHistoryListView()
                        .frame(minWidth: 200, idealWidth: 240)
                }
            }
            .background(ARESColors.background)
            .onAppear {
                appState.refreshSessionHistory()
                // Auto-focus chat input so typing works immediately
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    focusedField = .chatInput
                }
            }
            .onChange(of: appState.isViewingHistory) { _, viewing in
                if !viewing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedField = .chatInput
                    }
                }
            }
            .onChange(of: appState.isChatProcessing) { _, processing in
                // Re-focus after ARES finishes responding
                if !processing {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedField = .chatInput
                    }
                }
            }
        }
        .sheet(isPresented: $showSourcePicker) {
            SourceReferencePicker(
                sourceReaders: appState.sourceReaders,
                onAttach: { session in
                    appState.attachReference(session: session)
                    showSourcePicker = false
                },
                onCancel: { showSourcePicker = false }
            )
        }
    }

    // MARK: - Avatar panel

    private var avatarPanel: some View {
        VStack(spacing: 24) {
            Spacer()

            // Pulsing avatar ring
            ZStack {
                Circle()
                    .stroke(appState.voiceState.color.opacity(0.4), lineWidth: 2)
                    .frame(width: 200, height: 200)
                    .scaleEffect(showStats ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true),
                               value: showStats)

                Circle()
                    .fill(ARESColors.background)
                    .frame(width: 180, height: 180)

                Circle()
                    .fill(ARESColors.gradient)
                    .frame(width: 160, height: 160)

                Image(systemName: "shield.righthalf.filled")
                    .font(.system(size: 64))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.white.opacity(0.9), .white.opacity(0.3)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }

            // Voice state label
            Text(appState.voiceState.label.uppercased())
                .font(.caption)
                .fontWeight(.bold)
                .tracking(3)
                .foregroundStyle(appState.voiceState.color)

            Text(appState.companionGreeting.isEmpty ? "ARES online." : appState.companionGreeting)
                .font(.subheadline)
                .foregroundStyle(ARESColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            // Voice button (visual; full voice is not in scope yet)
            Button(action: { appState.voiceState = appState.voiceState == .listening ? .idle : .listening }) {
                HStack(spacing: 6) {
                    Image(systemName: appState.voiceState == .listening ? "mic.fill" : "mic")
                    Text(appState.voiceState == .listening ? "STOP" : "TALK")
                        .font(.caption)
                        .fontWeight(.bold)
                        .tracking(1)
                }
                .frame(width: 100, height: 36)
            }
            .buttonStyle(.borderedProminent)
            .tint(ARESColors.accent)

            // Stats toggle
            Button(action: { showStats.toggle() }) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                    Text(showStats ? "HIDE" : "STATS")
                        .font(.caption)
                        .fontWeight(.bold)
                        .tracking(1)
                }
                .frame(width: 100, height: 36)
            }
            .buttonStyle(.bordered)
            .tint(showStats ? ARESColors.gold : ARESColors.textSecondary)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Chat panel

    private var chatPanel: some View {
        VStack(spacing: 0) {
            chatHeader
            Divider().background(ARESColors.divider)

            // Show history banner when viewing a historical session
            if let histID = appState.viewingHistoricalSessionID {
                historyBanner(sessionID: histID)
                Divider().background(ARESColors.divider)
            }

            // Reference attachment bar
            if !appState.attachedReferences.isEmpty {
                referenceAttachmentBar
                Divider().background(ARESColors.divider)
            }

            // Content
            if showStats {
                statsGrid
            } else {
                conversationScroll
                inputBar
            }
        }
        .background(ARESColors.surface)
    }

    private var chatHeader: some View {
        HStack {
            Circle()
                .fill(appState.voiceState.color)
                .frame(width: 8, height: 8)
            Text("ARES")
                .font(.caption)
                .fontWeight(.bold)
                .tracking(2)
                .foregroundStyle(ARESColors.textSecondary)
            Spacer()
            // Model picker button — shows current model, opens popover on click.
            Button(action: { showModelPicker.toggle() }) {
                HStack(spacing: 4) {
                    Image(systemName: appState.voiceState == .thinking ? "brain" : "cpu")
                        .font(.caption2)
                    Text(appState.companionConfig.currentChoice.displayName)
                        .font(.caption2)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(ARESColors.surfaceElevated)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(ARESColors.divider, lineWidth: 1)
                )
                .foregroundStyle(ARESColors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Switch model — \(appState.companionConfig.model) via \(appState.companionConfig.provider)")
            .popover(isPresented: $showModelPicker, arrowEdge: .bottom) {
                ModelPickerView()
                    .environmentObject(appState)
            }
            Button(action: { showStats.toggle() }) {
                Image(systemName: showStats ? "chart.bar.fill" : "chart.bar")
                    .font(.caption)
                    .foregroundStyle(ARESColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func historyBanner(sessionID: String) -> some View {
        HStack {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(ARESColors.gold)
            Text("Viewing historical session: \(sessionID)")
                .font(.caption)
                .foregroundStyle(ARESColors.textSecondary)
            Spacer()
            Button("New Chat") {
                appState.startNewChat()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(ARESColors.gold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(ARESColors.gold.opacity(0.08))
    }

    // MARK: - Reference attachment bar

    private var referenceAttachmentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(appState.attachedReferences) { ref in
                    referenceChip(ref)
                }
                Button(action: { showSourcePicker = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill").font(.caption2)
                        Text("Add").font(.caption2)
                    }
                    .foregroundStyle(ARESColors.gold)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(ARESColors.gold.opacity(0.12))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func referenceChip(_ ref: AttachedReference) -> some View {
        HStack(spacing: 4) {
            Image(systemName: sourceIcon(for: ref.sourceName))
                .font(.caption2)
                .foregroundStyle(sourceColor(for: ref.sourceName))

            Text(ref.title ?? ref.sessionId)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(ARESColors.textPrimary)

            Text("·")
                .font(.caption2)
                .foregroundStyle(ARESColors.textTertiary)

            Text(ref.sourceName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(sourceColor(for: ref.sourceName))

            Button(action: { appState.removeReference(ref) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(ARESColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(ARESColors.surfaceElevated)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(ARESColors.divider, lineWidth: 1))
    }

    private func sourceIcon(for sourceName: String) -> String {
        switch sourceName {
        case "Claude Code": return "bubble.left.and.bubble.right"
        case "Gemini":      return "sparkles"
        case "Odysseus":    return "compass"
        case "Hermes":      return "bolt.horizontal"
        default:            return "doc.text"
        }
    }

    private func sourceColor(for sourceName: String) -> Color {
        switch sourceName {
        case "Claude Code": return .orange
        case "Gemini":      return .blue
        case "Odysseus":    return .purple
        case "Hermes":      return ARESColors.gold
        default:            return ARESColors.textSecondary
        }
    }

    // MARK: - Conversation scroll

    @ViewBuilder
    private var conversationScroll: some View {
        let messagesToShow: [ChatBubble] = appState.isViewingHistory
            ? appState.historicalMessages
            : appState.chatMessages

        if messagesToShow.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(messagesToShow) { bubble in
                            bubbleRow(bubble)
                                .id(bubble.id)
                        }
                    }
                    .padding(16)
                    .onChange(of: messagesToShow.last?.content) { _, _ in
                        // Auto-scroll to bottom when new tokens arrive
                        if let lastID = messagesToShow.last?.id {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: messagesToShow.count) { _, newCount in
                        // Scroll when a new message appears
                        if let lastID = messagesToShow.last?.id {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(lastID, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "shield.righthalf.filled")
                .font(.largeTitle)
                .foregroundStyle(ARESColors.gold.opacity(0.4))
            Text(appState.isViewingHistory ? "No messages in this session." : "ARES is ready.")
                .font(.subheadline)
                .foregroundStyle(ARESColors.textTertiary)
            Spacer()
        }
    }

    private func bubbleRow(_ bubble: ChatBubble) -> some View {
        HStack(alignment: .top) {
            if bubble.role == .user {
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    if let refs = bubble.references, !refs.isEmpty {
                        referenceChipsLine(refs)
                    }
                    if bubble.id == editingMessageId {
                        editModeView(bubble)
                    } else {
                        messageBubble(bubble)
                            .contextMenu {
                                Button("Copy") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(bubble.content, forType: .string)
                                }
                                Button("Copy as Markdown") {
                                    NSPasteboard.general.clearContents()
                                    let md = formatAsMarkdown(bubble)
                                    NSPasteboard.general.setString(md, forType: .string)
                                }
                                Divider()
                                if !appState.isViewingHistory {
                                    Button("Edit") {
                                        beginEdit(bubble)
                                    }
                                    Button("Delete Message", role: .destructive) {
                                        deleteMessage(bubble)
                                    }
                                }
                                if !appState.isViewingHistory {
                                    Divider()
                                    Button("Branch from here") {
                                        branchFrom(bubble)
                                    }
                                }
                            }
                    }
                    branchMarker(bubble)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    messageBubble(bubble)
                        .contextMenu {
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(bubble.content, forType: .string)
                            }
                            Button("Copy as Markdown") {
                                NSPasteboard.general.clearContents()
                                let md = formatAsMarkdown(bubble)
                                NSPasteboard.general.setString(md, forType: .string)
                            }
                            Divider()
                            if !appState.isViewingHistory {
                                Button("Regenerate Response") {
                                    regenerateFrom(bubble: bubble)
                                }
                                Button("Delete Message", role: .destructive) {
                                    deleteMessage(bubble)
                                }
                            }
                            if !appState.isViewingHistory {
                                Divider()
                                Button("Branch from here") {
                                    branchFrom(bubble)
                                }
                            }
                        }
                    branchMarker(bubble)
                }
                Spacer()
            }
        }
    }

    /// Renders a chat bubble. Text is selectable (so Cmd+C works) but
    /// the rest of the row doesn't fight you for focus. Assistant
    /// messages get Markdown rendering (bold, code, lists, links).
    /// Streaming bubbles show a blinking cursor.
    private func messageBubble(_ bubble: ChatBubble) -> some View {
        Group {
            if bubble.role == .assistant, let attributed = try? AttributedString(
                markdown: bubble.content,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            ) {
                Text(attributed) + (bubble.isStreaming ? Text("▊").foregroundStyle(ARESColors.gold).fontWeight(.bold) : Text(""))
            } else {
                Text(bubble.content) + (bubble.isStreaming ? Text("▊").foregroundStyle(ARESColors.gold).fontWeight(.bold) : Text(""))
            }
        }
        .textSelection(.enabled)
        .padding(10)
        .background(bubble.role == .user
                    ? ARESColors.accent.opacity(0.25)
                    : ARESColors.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .foregroundStyle(ARESColors.textPrimary)
        .frame(maxWidth: .infinity, alignment: bubble.role == .user ? .trailing : .leading)
        .textSelection(.enabled)
    }

    /// Format a message for clipboard as Markdown. Assistant messages
    /// get a role header; user messages get the verbatim content.
    private func formatAsMarkdown(_ bubble: ChatBubble) -> String {
        switch bubble.role {
        case .user:
            return bubble.content
        case .assistant:
            return "**ARES**\n\n\(bubble.content)"
        }
    }

    private func deleteMessage(_ bubble: ChatBubble) {
        let target: [ChatBubble] = appState.isViewingHistory
            ? appState.historicalMessages
            : appState.chatMessages
        if let idx = target.firstIndex(where: { $0.id == bubble.id }) {
            appState.removeChatMessage(at: idx)
        }
    }

    private func regenerateFrom(bubble: ChatBubble) {
        let msgs = appState.chatMessages
        guard let assistantIdx = msgs.firstIndex(where: { $0.id == bubble.id }),
              let userIdx = msgs[..<assistantIdx].lastIndex(where: { $0.role == .user })
        else { return }
        // Truncate at the user message and re-send.
        appState.truncateAndResend(at: userIdx)
    }

    private func referenceChipsLine(_ refs: [AttachedReference]) -> some View {
        HStack(spacing: 4) {
            ForEach(refs) { ref in
                HStack(spacing: 2) {
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 9))
                    Text(ref.sourceName)
                        .font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(sourceColor(for: ref.sourceName).opacity(0.15))
                .clipShape(Capsule())
            }
        }
    }

    // MARK: - Edit & Branch helpers

    /// Displays a TextField with Cancel / Save & Resend buttons for editing.
    @ViewBuilder
    private func editModeView(_ bubble: ChatBubble) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            TextField("Edit message…", text: $editText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(10)
                .background(ARESColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(ARESColors.gold.opacity(0.5), lineWidth: 1)
                )
                .foregroundStyle(ARESColors.textPrimary)
                .onSubmit { saveEdit(bubble) }

            HStack(spacing: 8) {
                Button("Cancel") {
                    cancelEdit()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Save & Resend") {
                    saveEdit(bubble)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(ARESColors.gold)
            }
        }
        .frame(maxWidth: 400)
    }

    /// Enters edit mode for the given user bubble.
    private func beginEdit(_ bubble: ChatBubble) {
        editingMessageId = bubble.id
        editText = bubble.content
    }

    /// Saves the edited content, re-sends from this bubble, and exits edit mode.
    private func saveEdit(_ bubble: ChatBubble) {
        let msgs = appState.chatMessages
        guard let idx = msgs.firstIndex(where: { $0.id == bubble.id }) else {
            cancelEdit()
            return
        }
        appState.editMessage(at: idx, newContent: editText)
        editingMessageId = nil
        editText = ""
    }

    /// Exits edit mode without saving.
    private func cancelEdit() {
        editingMessageId = nil
        editText = ""
    }

    /// Branches the conversation from the selected bubble.
    private func branchFrom(_ bubble: ChatBubble) {
        let msgs = appState.chatMessages
        guard let idx = msgs.firstIndex(where: { $0.id == bubble.id }) else { return }
        // If we're currently editing, cancel first
        cancelEdit()
        appState.branchFromMessage(at: idx)
    }

    /// Small visual indicator shown on the first bubble of a branched session.
    @ViewBuilder
    private func branchMarker(_ bubble: ChatBubble) -> some View {
        if bubble.parentBranchId != nil {
            Text("\u{21B3} branched")
                .font(.caption2)
                .foregroundStyle(ARESColors.textTertiary)
                .padding(.top, 1)
        }
    }

    // MARK: - Input bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().background(ARESColors.divider)
            HStack(alignment: .bottom, spacing: 8) {
                // Attach reference button (hidden during streaming)
                if !appState.isChatProcessing {
                    Button(action: { showSourcePicker = true }) {
                        Image(systemName: "plus.circle")
                            .font(.title3)
                            .foregroundStyle(ARESColors.gold)
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.isViewingHistory)
                    .help("Attach a session reference")
                }

                // Text input
                TextField(
                    appState.isViewingHistory ? "Historical session — read only" : (appState.isChatProcessing ? "ARES is responding…" : "Message ARES…"),
                    text: $appState.chatInput,
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .focused($focusedField, equals: .chatInput)
                .disabled(appState.isViewingHistory || appState.isChatProcessing)
                .onSubmit {
                    if !appState.isChatProcessing && !appState.isViewingHistory {
                        appState.sendChat()
                    }
                }

                // Send button (when idle) / Cancel button (when streaming)
                if appState.isChatProcessing {
                    Button(action: { appState.cancelStreaming() }) {
                        Image(systemName: "stop.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                    .help("Cancel response")
                } else {
                    Button(action: appState.sendChat) {
                        Image(systemName: "paperplane.fill")
                            .foregroundStyle(ARESColors.gold)
                    }
                    .buttonStyle(.plain)
                    .disabled(
                        appState.isViewingHistory
                        || appState.chatInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    )
                }
            }
            .padding(12)
        }
    }

    // MARK: - Stats grid

    private var statsGrid: some View {
        ScrollView {
            VStack(spacing: 16) {
                StatCard(title: "SESSIONS", value: "\(appState.sessionCount)", icon: "bubble.left.and.bubble.right", color: ARESColors.gold)
                StatCard(title: "SKILLS",   value: "\(appState.skillCount)",   icon: "book.closed",              color: ARESColors.accent)
                StatCard(title: "MEMORY",   value: "\(appState.memoryPercent)%", icon: "brain.head.profile",      color: ARESColors.green)
                StatCard(title: "AGENTS",   value: "\(appState.activeOfficeAgents)", icon: "person.3",            color: ARESColors.purple)
            }
            .padding(16)
        }
    }
}


// MARK: - Model picker
//
// Popover that lets the user pick which (provider, model) pair
// ARES uses to talk to Hermes. Inspired by Xcode's "Model" picker
// in the chat panel — search, group by Local/Cloud/Frontier, show
// speed + quality hints. Selection persists in UserDefaults via
// CompanionConfig.

struct ModelPickerView: View {
    @EnvironmentObject private var appState: ARESAppState
    @State private var searchText: String = ""

    private var filtered: [CompanionConfig.Choice] {
        let q = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return CompanionConfig.allChoices }
        return CompanionConfig.allChoices.filter {
            $0.displayName.lowercased().contains(q) ||
            $0.provider.lowercased().contains(q) ||
            $0.model.lowercased().contains(q) ||
            $0.summary.lowercased().contains(q)
        }
    }

    private var grouped: [(CompanionConfig.Choice.Group, [CompanionConfig.Choice])] {
        let groups = Dictionary(grouping: filtered, by: \.group)
        return CompanionConfig.Choice.Group.allCases.compactMap { g in
            guard let list = groups[g]?.sorted(by: { $0.displayName < $1.displayName }),
                  !list.isEmpty else { return nil }
            return (g, list)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "cpu")
                    .foregroundStyle(ARESColors.gold)
                Text("Model")
                    .font(.headline)
                    .foregroundStyle(ARESColors.textPrimary)
                Spacer()
                Text(appState.companionConfig.model)
                    .font(.caption2)
                    .fontDesign(.monospaced)
                    .foregroundStyle(ARESColors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(ARESColors.textTertiary)
                TextField("Search models...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(ARESColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 14)
            .padding(.bottom, 10)

            Divider().background(ARESColors.divider)

            // List
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(grouped, id: \.0) { group, choices in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.displayName.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .tracking(2)
                                .foregroundStyle(ARESColors.textTertiary)
                                .padding(.horizontal, 14)

                            ForEach(choices) { choice in
                                Button {
                                    appState.companionConfig = CompanionConfig(
                                        model: choice.model,
                                        provider: choice.provider
                                    )
                                    appState.companionConfig.save()
                                } label: {
                                    choiceRow(choice)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.vertical, 12)
            }
            .frame(width: 360, height: 440)
        }
        .background(ARESColors.surface)
    }

    @ViewBuilder
    private func choiceRow(_ choice: CompanionConfig.Choice) -> some View {
        let isCurrent = choice.provider == appState.companionConfig.provider
                    && choice.model == appState.companionConfig.model
        HStack(alignment: .top, spacing: 10) {
            // Radio dot
            ZStack {
                Circle()
                    .stroke(isCurrent ? ARESColors.gold : ARESColors.divider, lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                if isCurrent {
                    Circle()
                        .fill(ARESColors.gold)
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(choice.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(ARESColors.textPrimary)
                    Spacer()
                    speedBadge(choice.speed)
                    qualityBadge(choice.quality)
                }
                Text(choice.summary)
                    .font(.caption2)
                    .foregroundStyle(ARESColors.textSecondary)
                    .lineLimit(2)
                Text("\\(choice.provider) / \\(choice.model)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(ARESColors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(isCurrent ? ARESColors.gold.opacity(0.10) : Color.clear)
    }

    private func speedBadge(_ s: CompanionConfig.Choice.Speed) -> some View {
        let color: Color = {
            switch s {
            case .fast:   return .green
            case .medium: return .yellow
            case .slow:   return .red
            }
        }()
        return HStack(spacing: 2) {
            Image(systemName: s.icon)
                .font(.system(size: 8))
            Text(s.rawValue)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 5)
        .padding(.vertical, 1)
        .background(color.opacity(0.12))
        .clipShape(Capsule())
    }

    private func qualityBadge(_ q: CompanionConfig.Choice.Quality) -> some View {
        Text(q.label)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(ARESColors.textTertiary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(
                Capsule().stroke(ARESColors.divider, lineWidth: 0.5)
            )
            .clipShape(Capsule())
    }
}

// MARK: - Source reference picker sheet

/// Sheet for picking a session from any installed tool to attach as a
/// reference to the next ARES message. Read-only — we never write to the
/// source tool's data store.
struct SourceReferencePicker: View {
    let sourceReaders: [any SourceReader]
    let onAttach: (UnifiedSession) -> Void
    let onCancel: () -> Void

    @State private var selectedSource: String
    @State private var sessions: [UnifiedSession] = []
    @State private var isLoading: Bool = false
    @State private var searchText: String = ""

    private let sourceOptions: [(String, String, String)] = [
        ("claude_code", "Claude Code", "bubble.left.and.bubble.right"),
        ("gemini",      "Gemini",      "sparkles"),
        ("odysseus",    "Odysseus",    "compass"),
        ("hermes",      "Hermes",      "bolt.horizontal")
    ]

    init(
        sourceReaders: [any SourceReader],
        onAttach: @escaping (UnifiedSession) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sourceReaders = sourceReaders
        self.onAttach = onAttach
        self.onCancel = onCancel
        _selectedSource = State(initialValue: sourceReaders.first?.sourceName ?? "claude_code")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Attach Session Reference")
                    .font(.headline)
                Spacer()
                Button("Cancel", action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(ARESColors.textSecondary)
            }
            .padding(16)

            Divider()

            // Source picker
            Picker("Source", selection: $selectedSource) {
                ForEach(sourceOptions, id: \.0) { option in
                    HStack {
                        Image(systemName: option.2)
                        Text(option.1)
                    }
                    .tag(option.0)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .onChange(of: selectedSource) { _, _ in
                loadSessions()
            }

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(ARESColors.textTertiary)
                TextField("Search sessions…", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(ARESColors.background.opacity(0.8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Session list
            if isLoading {
                Spacer()
                ProgressView("Loading sessions…")
                Spacer()
            } else if filteredSessions.isEmpty {
                Spacer()
                Text("No sessions found for \(displayName).")
                    .font(.subheadline)
                    .foregroundStyle(ARESColors.textTertiary)
                Spacer()
            } else {
                List(filteredSessions) { session in
                    Button(action: { onAttach(session) }) {
                        sessionRow(session)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(ARESColors.surface)
        .onAppear { loadSessions() }
    }

    private var filteredSessions: [UnifiedSession] {
        if searchText.isEmpty { return sessions }
        return sessions.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }

    private var displayName: String {
        sourceOptions.first(where: { $0.0 == selectedSource })?.1 ?? selectedSource
    }

    private func sessionRow(_ session: UnifiedSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title ?? session.id)
                .font(.body)
                .lineLimit(1)
                .foregroundStyle(ARESColors.textPrimary)
            HStack(spacing: 6) {
                if let date = session.updatedAt {
                    Text(DateFormatters.shortDateTimeString(from: date))
                        .font(.caption2)
                        .foregroundStyle(ARESColors.textTertiary)
                }
                if let count = session.messageCount, count > 0 {
                    Text("· \(count) messages")
                        .font(.caption2)
                        .foregroundStyle(ARESColors.textTertiary)
                }
                if let ws = session.workspace {
                    Text("· \(ws)")
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundStyle(ARESColors.textTertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func loadSessions() {
        isLoading = true
        sessions = []
        guard let reader = sourceReaders.first(where: { $0.sourceName == selectedSource }) else {
            isLoading = false
            return
        }
        Task {
            // Reader is a class; listSessions is synchronous; offload to background
            // by using a Task without `@MainActor`. Reader methods only touch the
            // filesystem, so it's safe to call from any executor.
            let result = (try? reader.listSessions()) ?? []
            await MainActor.run {
                sessions = result
                isLoading = false
            }
        }
    }
}
