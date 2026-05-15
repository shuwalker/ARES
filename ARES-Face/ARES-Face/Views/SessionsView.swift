import SwiftUI

/// Session list view — shows Hermes sessions from the dashboard API.
/// Hermes-inspired: list + search + selection + detail push.
struct SessionsView: View {
    @State private var sessions: [Session] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedSession: Session?
    @State private var detail: SessionDetail?
    @State private var showDetail = false

    var filteredSessions: [Session] {
        if searchText.isEmpty { return sessions }
        return sessions.filter { s in
            (s.preview?.localizedCaseInsensitiveContains(searchText) ?? false) ||
            s.id.localizedCaseInsensitiveContains(searchText) ||
            (s.model?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            toolbar

            Divider()
                .background(ARESPalette.surfaceBorder)

            // Content
            if isLoading {
                loadingState
            } else if let error = errorMessage {
                errorState(error)
            } else {
                sessionList
            }
        }
        .onAppear { loadSessions() }
        .sheet(item: $selectedSession) { session in
            SessionDetailSheet(session: session)
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Sessions")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                TextField("Search...", text: $searchText)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
                    .frame(width: 180)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.white.opacity(0.04))
            .cornerRadius(6)

            // Refresh
            Button {
                loadSessions()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    )
            }
            .buttonStyle(.plain)
            .help("Refresh sessions")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.15))
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView("Loading sessions...")
                .controlSize(.small)
            Spacer()
        }
    }

    // MARK: - Error State

    private func errorState(_ error: String) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("Retry") { loadSessions() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Spacer()
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(filteredSessions) { session in
                    SessionListRow(session: session)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedSession = session
                        }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(Color.clear)
    }

    // MARK: - Data

    private func loadSessions() {
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
}

// MARK: - Session List Row

struct SessionListRow: View {
    let session: Session
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Status dot
            statusCircle

            VStack(alignment: .leading, spacing: 3) {
                // Title
                Text(session.preview ?? "Session \(session.id.prefix(12))...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.9))
                    .lineLimit(1)

                // Meta row
                HStack(spacing: 10) {
                    if let model = session.model {
                        metaBadge(model, color: .cyan)
                    }
                    if let source = session.source {
                        metaBadge(source, color: .secondary)
                    }
                    if let count = session.messageCount {
                        metaBadge("\(count) messages", color: .secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Timestamp
            if let last = session.lastActive {
                Text(formatTimestamp(last))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary.opacity(0.5))
            }

            // Chevron
            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.3))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.04) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isHovered ? ARESPalette.surfaceBorder : Color.clear, lineWidth: 0.5)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var statusCircle: some View {
        Circle()
            .fill(session.isActive == true ? Color.green : Color.gray.opacity(0.4))
            .frame(width: 8, height: 8)
            .shadow(
                color: session.isActive == true ? Color.green.opacity(0.3) : .clear,
                radius: 3
            )
    }

    private func metaBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(color.opacity(0.7))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
    }

    private func formatTimestamp(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts)
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}

// MARK: - Session Detail Sheet

struct SessionDetailSheet: View {
    let session: Session
    @Environment(\.dismiss) var dismiss
    @State private var detail: SessionDetail?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Session Detail")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            .padding()

            Divider()
                .background(ARESPalette.surfaceBorder)

            if isLoading {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else if let detail = detail, let msgs = detail.messages {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let s = detail.session {
                            infoRow("ID", s.id)
                            if let model = s.model {
                                infoRow("Model", model)
                            }
                            if let source = s.source {
                                infoRow("Source", source)
                            }
                            if let count = s.messageCount {
                                infoRow("Messages", "\(count)")
                            }
                        }

                        Divider()
                            .background(ARESPalette.surfaceBorder)

                        // Messages
                        ForEach(msgs) { msg in
                            messageCard(msg)
                        }
                    }
                    .padding()
                }
            } else {
                Spacer()
                Text("No messages in session")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .frame(width: 560, height: 500)
        .onAppear { loadDetail() }
    }

    private func loadDetail() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                detail = try await HermesDashboardService.shared.getSessionDetail(session.id)
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func messageCard(_ msg: SessionMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(msg.role.capitalized)
                    .font(.system(size: 10, weight: .semibold).lowercaseSmallCaps())
                    .foregroundStyle(msg.role == "user" ? ARESPalette.accent : .green)
                Spacer()
                if let ts = msg.timestamp {
                    Text(formatTimestamp(ts))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary.opacity(0.5))
                }
            }
            Text(msg.content)
                .font(.system(size: 12))
                .foregroundStyle(.primary.opacity(0.8))
                .lineLimit(5)
                .textSelection(.enabled)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(ARESPalette.surfaceBorder, lineWidth: 0.5)
                )
        )
    }

    private func formatTimestamp(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts)
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: d)
    }
}
