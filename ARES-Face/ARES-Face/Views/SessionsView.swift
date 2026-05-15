import SwiftUI

/// Session list view — shows Hermes sessions from the dashboard API.
/// From OS1 pattern: list + search + delete + detail push.
struct SessionsView: View {
    @State private var sessions: [Session] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var selectedSession: Session?
    
    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search sessions...", text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit { loadSessions() }
                if !searchText.isEmpty {
                    Button { searchText = ""; loadSessions() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }.buttonStyle(.plain)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial)
            
            // Content
            if isLoading {
                Spacer()
                ProgressView("Loading sessions...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { loadSessions() }
                        .buttonStyle(.bordered)
                }
                Spacer()
            } else if sessions.isEmpty {
                Spacer()
                Text("No sessions found")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(sessions.filter { s in
                    searchText.isEmpty || 
                    (s.preview?.localizedCaseInsensitiveContains(searchText) ?? false) ||
                    (s.id.localizedCaseInsensitiveContains(searchText))
                }, selection: $selectedSession) { session in
                    SessionRow(session: session)
                        .tag(session)
                }
                .listStyle(.inset)
            }
        }
        .onAppear { loadSessions() }
    }
    
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

struct SessionRow: View {
    let session: Session
    
    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(session.isActive == true ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(session.preview ?? "Session \(session.id.prefix(12))...")
                    .lineLimit(1)
                    .font(.body)
                HStack(spacing: 8) {
                    if let model = session.model {
                        Text(model).font(.caption).foregroundStyle(.teal)
                    }
                    if let source = session.source {
                        Text(source).font(.caption).foregroundStyle(.secondary)
                    }
                    if let count = session.messageCount {
                        Text("\(count) msgs").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            if let last = session.lastActive {
                Text(formatTimestamp(last))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatTimestamp(_ ts: Double) -> String {
        let d = Date(timeIntervalSince1970: ts)
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: d, relativeTo: Date())
    }
}