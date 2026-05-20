import SwiftUI

struct SwarmRuntimeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Error banner at top
            if let error = appState.swarmError {
                SwarmErrorBanner(message: error) { appState.swarmError = nil }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
            }

            HSplitView {
                workerList
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)

                terminalPane
                    .frame(minWidth: 320, maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { appState.startSwarmRuntimePolling() }
        .onDisappear { appState.stopSwarmRuntimePolling() }
    }

    private var workerList: some View {
        List(selection: Binding(
            get: { appState.swarmSelectedWorker?.id },
            set: { id in
                appState.swarmSelectedWorker = appState.swarmWorkers.first(where: { $0.id == id })
            }
        )) {
            ForEach(appState.swarmWorkers) { worker in
                HStack(spacing: 8) {
                    Circle()
                        .fill(workerStatusColor(worker))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(worker.name)
                            .font(.body)
                            .lineLimit(1)
                        Text(worker.role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tag(worker.id)
                .padding(.vertical, 2)
            }
        }
        .listStyle(.sidebar)
    }

    private var terminalPane: some View {
        Group {
            if let worker = appState.swarmSelectedWorker {
                let output = appState.swarmRuntimeOutput[worker.id]
                    ?? appState.swarmRuntimeOutput[worker.name]
                    ?? appState.swarmRuntimeOutput["default"]
                    ?? ""
                SwarmTerminalView(workerName: worker.name, output: output)
            } else {
                ContentUnavailableView(
                    "Select a Worker",
                    systemImage: "terminal",
                    description: Text("Select a worker from the list to view its terminal output.")
                )
            }
        }
    }

    private func workerStatusColor(_ worker: SwarmWorker) -> Color {
        switch worker.status {
        case "active": return .green
        case "idle": return .yellow
        default: return Color.secondary.opacity(0.4)
        }
    }
}

// MARK: - Terminal View

struct SwarmTerminalView: View {
    let workerName: String
    let output: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "terminal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(workerName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(HermesTheme.aresSurface.opacity(0.6))

            ScrollViewReader { proxy in
                ScrollView {
                    Text(output.isEmpty ? "No output yet." : output)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(output.isEmpty ? Color.secondary : Color.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .id("bottom")
                }
                .onChange(of: output) { _, _ in
                    withAnimation {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
                .onAppear {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }
}
