import SwiftUI

/// Interactive memory inspector — search past sessions, recall context, browse memories.
///
/// Connects to HermesDashboardService for session search and BrainConnection for
/// cognitive memory recall. Not a passive log — this is an active tool:
/// tap a memory to inject it into the chat context, search to find what ARES knows.
///
/// Session detail drill-in: tap a session row to see full conversation history,
/// message counts, model used, and token usage. Tap individual messages to copy
/// or inject them into the current chat context.
struct MemoryInspectorView: View {
    @EnvironmentObject var brain: BrainConnection
    @State private var searchText = ""
    @State private var sessions: [Session] = []
    @State private var selectedSession: SessionDetail?
    @State private var showingSessionDetail = false
    @State private var isLoading = false
    @State private var isLoadingDetail = false
    @State private var errorMessage: String?
    @State private var cognitiveHits: [MemoryHitBlock] = []

    var body: some View {
        VStack(spacing: 0) {
            // ── Search bar ──
            searchBar
            Divider().background(.white.opacity(0.08))

            // ── Content ──
            if isLoading {
                Spacer()
                ProgressView("Searching memories...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                errorView(error)
                Spacer()
            } else {
                contentList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
        .onAppear { loadCognitiveHits() }
        .onChange(of: brain.cognitive.memoryRecall) { _, newHits in
            cognitiveHits = newHits
        }
        .sheet(isPresented: $showingSessionDetail) {
            if let detail = selectedSession {
                SessionDetailView(detail: detail, brain: brain)
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .foregroundStyle(.secondary)
            TextField("Search memories...", text: $searchText)
                .textFieldStyle(.plain)
                .onSubmit { searchSessions() }
            if !searchText.isEmpty {
                Button { searchText = ""; sessions = [] } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button { searchSessions() } label: {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.cyan)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Content

    private var contentList: some View {
        List {
            // Cognitive recall section (from current session)
            if !cognitiveHits.isEmpty {
                Section {
                    ForEach(cognitiveHits) { hit in
                        memoryHitRow(hit)
                    }
                } header: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                        Text("Current Recall")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.cyan)
                }
            }

            // Session search results
            if !sessions.isEmpty {
                Section {
                    ForEach(sessions) { session in
                        sessionRow(session)
                            .onTapGesture { loadSessionDetail(session) }
                    }
                } header: {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption2)
                        Text("Past Sessions")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(.secondary)
                }
            }

            // Empty state
            if cognitiveHits.isEmpty && sessions.isEmpty && searchText.isEmpty {
                emptyState
            }
        }
        .listStyle(.inset)
    }

    // MARK: - Memory Hit Row

    private func memoryHitRow(_ hit: MemoryHitBlock) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(hit.kind)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
            if !hit.text.isEmpty {
                Text(hit.text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            HStack(spacing: 4) {
                Text(hit.id)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if hit.score > 0 {
                    Text("\(Int(hit.score * 100))% match")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.cyan.opacity(0.7))
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copy") {
                copyToPasteboard(hit.text)
            }
            Button("Send to chat") {
                brain.sendMessage("Recall: \(hit.kind)")
            }
        }
    }

    // MARK: - Session Row

    private func sessionRow(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.preview ?? session.id)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            if let model = session.model, !model.isEmpty {
                Text(model)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 6) {
                if let count = session.messageCount {
                    Text("\(count) msgs")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if session.isActive == true {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 5, height: 5)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("ARES Memory")
                .font(.headline)
            Text("Search past conversations and recalled knowledge")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: - Error View

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Retry") { searchSessions() }
                .buttonStyle(.bordered)
        }
    }

    // MARK: - Actions

    private func searchSessions() {
        guard !searchText.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                sessions = try await HermesDashboardService.shared.listSessions(query: searchText)
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func loadSessionDetail(_ session: Session) {
        isLoadingDetail = true
        Task {
            do {
                selectedSession = try await HermesDashboardService.shared.getSessionDetail(session.id)
                isLoadingDetail = false
                showingSessionDetail = true
            } catch {
                errorMessage = error.localizedDescription
                isLoadingDetail = false
            }
        }
    }

    private func loadCognitiveHits() {
        cognitiveHits = brain.cognitive.memoryRecall
    }

    private func copyToPasteboard(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Session Detail Drill-In

/// Full conversation detail for a past session.
/// Shows all messages, metadata, and allows copying/injecting individual messages.
struct SessionDetailView: View {
    let detail: SessionDetail
    @ObservedObject var brain: BrainConnection
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // ── Header ──
            detailHeader

            Divider().background(.white.opacity(0.08))

            // ── Messages ──
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(filteredMessages) { msg in
                        sessionMessageRow(msg)
                    }
                }
                .padding(14)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .background(.ultraThinMaterial)
    }

    // MARK: - Detail Header

    private var detailHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(detail.session?.preview ?? "Session Detail")
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        if let model = detail.session?.model, !model.isEmpty {
                            Label(model, systemImage: "cpu")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let count = detail.session?.messageCount {
                            Label("\(count) messages", systemImage: "bubble.left.and.bubble.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let msgCount = detail.messages?.count, msgCount > 0 {
                            Label("\(msgCount) loaded", systemImage: "arrow.down.doc")
                                .font(.caption2)
                                .foregroundStyle(.cyan.opacity(0.7))
                        }
                    }
                }
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
            }

            // Search within session
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Search in session...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06))
            .cornerRadius(6)
        }
        .padding(14)
    }

    // MARK: - Message Row

    private func sessionMessageRow(_ msg: SessionMessage) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: msg.role == "user" ? "person.fill" : "flame.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(msg.role == "user" ? .blue : .cyan)
                Text(msg.role.capitalized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if let ts = msg.timestamp {
                    Text(formatTimestamp(ts))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            Text(msg.content)
                .font(.system(size: 12))
                .lineLimit(searchText.isEmpty ? 5 : nil)
                .foregroundStyle(.primary)
        }
        .padding(8)
        .background(Color.white.opacity(msg.role == "user" ? 0.04 : 0.02))
        .cornerRadius(6)
        .contextMenu {
            Button("Copy message") {
                #if os(macOS)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(msg.content, forType: .string)
                #endif
            }
            Button("Send to current chat") {
                brain.sendMessage("Context from previous session: \(msg.content.prefix(200))")
            }
        }
    }

    // MARK: - Filtering

    private var filteredMessages: [SessionMessage] {
        let allMessages = detail.messages ?? []
        if searchText.isEmpty {
            return allMessages
        }
        return allMessages.filter { msg in
            msg.content.localizedCaseInsensitiveContains(searchText) ||
            msg.role.localizedCaseInsensitiveContains(searchText)
        }
    }

    // MARK: - Helpers

    private func formatTimestamp(_ ts: Double) -> String {
        let date = Date(timeIntervalSince1970: ts)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}