import SwiftUI

struct LogsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var logLines: [LogLine] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedFile = "agent"
    @State private var selectedLevel = "ALL"
    @State private var selectedLineCount = 200
    @State private var searchText = ""
    @State private var autoScroll = true

    private let files = ["agent", "errors", "gateway"]
    private let levels = ["ALL", "DEBUG", "INFO", "WARNING", "ERROR"]
    private let lineCounts = [50, 100, 200, 500]

    var body: some View {
        HermesPageContainer(width: .analytics) {
            VStack(alignment: .leading, spacing: 16) {
                HermesPageHeader(
                    title: "Logs",
                    subtitle: "View Hermes agent, gateway, and error logs in real time."
                )

                filterBar

                logsContent
            }
            .overlay(alignment: .topTrailing) {
                if isLoading && logLines.isEmpty {
                    HermesLoadingOverlay()
                        .padding(18)
                }
            }
        }
        .task(id: appState.activeConnectionID) {
            await loadLogs()
        }
    }

    private var filterBar: some View {
        HermesSurfacePanel {
            HStack(spacing: 16) {
                Picker("File", selection: $selectedFile) {
                    ForEach(files, id: \.self) { f in
                        Text(f.capitalized).tag(f)
                    }
                }
                .frame(width: 110)

                Picker("Level", selection: $selectedLevel) {
                    ForEach(levels, id: \.self) { l in
                        Text(l).tag(l)
                    }
                }
                .frame(width: 100)

                Picker("Lines", selection: $selectedLineCount) {
                    ForEach(lineCounts, id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .frame(width: 80)

                Spacer()

                HStack(spacing: 8) {
                    TextField("Filter…", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 160)

                    Button {
                        Task { await loadLogs() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Toggle("Auto-scroll", isOn: $autoScroll)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }
            }
        }
    }

    @ViewBuilder
    private var logsContent: some View {
        if isLoading && logLines.isEmpty {
            HermesSurfacePanel {
                HermesLoadingState(label: "Loading logs…", minHeight: 400)
            }
        } else if let error = errorMessage {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "Unable to load logs",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 400)
            }
        } else if logLines.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "No log entries",
                    systemImage: "doc.text",
                    description: Text("No log entries match the current filter.")
                )
                .frame(maxWidth: .infinity, minHeight: 400)
            }
        } else {
            logLinesView
        }
    }

    private var logLinesView: some View {
        HermesSurfacePanel {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredLines, id: \.identifier) { line in
                            logLineRow(line)
                                .id(line.identifier)
                        }
                    }
                }
                .onChange(of: logLines.count) {
                    if autoScroll, let last = filteredLines.last {
                        withAnimation {
                            proxy.scrollTo(last.identifier, anchor: .bottom)
                        }
                    }
                }
            }
            .font(.system(.caption, design: .monospaced))
        }
    }

    private func logLineRow(_ line: LogLine) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if let timestamp = line.timestamp, !timestamp.isEmpty {
                Text(timestamp)
                    .foregroundStyle(.tertiary)
                    .frame(width: 80, alignment: .trailing)
            }

            Text(line.text)
                .foregroundStyle(colorForLevel(line.level))
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
        .padding(.horizontal, 4)
    }

    private var filteredLines: [LogLine] {
        if searchText.isEmpty {
            return logLines
        }
        return logLines.filter { $0.text.lowercased().contains(searchText) }
    }

    private func colorForLevel(_ level: String?) -> Color {
        guard let lvl = level?.uppercased() else { return .primary }
        if lvl.contains("ERROR") || lvl.contains("CRITICAL") || lvl.contains("FATAL") { return .red }
        if lvl.contains("WARNING") || lvl.contains("WARN") { return .orange }
        if lvl.contains("DEBUG") { return .secondary }
        return .primary
    }

    // MARK: - Data Loading

    private func loadLogs() async {
        guard let connection = appState.activeConnection, connection.transportKind == .local else {
            errorMessage = "Logs require a local Hermes connection."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let response = try await appState.dashboardAPIService.fetchLogs(
                file: selectedFile,
                level: selectedLevel,
                lines: selectedLineCount
            )
            logLines = response.lines
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}