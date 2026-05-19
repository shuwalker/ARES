import SwiftUI

struct SwarmOverviewView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showDispatchSheet = false
    @State private var showWorkerDetail = false

    var body: some View {
        HermesPageContainer(width: .dashboard) {
            VStack(alignment: .leading, spacing: 20) {
                HermesPageHeader(
                    title: "Swarm",
                    subtitle: "Live multi-agent digital office. Watch your AI team work in real time."
                ) {
                    Button {
                        showDispatchSheet = true
                    } label: {
                        Label("Dispatch Mission", systemImage: "paperplane")
                    }
                    .buttonStyle(.borderedProminent)
                }

                healthBar

                if appState.isLoadingSwarm && appState.swarmWorkers.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if appState.swarmWorkers.isEmpty {
                    ContentUnavailableView(
                        "No Workers Found",
                        systemImage: "person.3",
                        description: Text("The swarm roster is empty or could not be loaded.")
                    )
                } else {
                    workerGrid
                }
            }
        }
        .sheet(isPresented: $showDispatchSheet) {
            SwarmDispatchSheet()
        }
        .sheet(isPresented: $showWorkerDetail) {
            if let worker = appState.swarmSelectedWorker {
                SwarmWorkerDetailSheet(worker: worker)
            }
        }
        .onChange(of: appState.swarmSelectedWorker) { _, worker in
            if worker != nil { showWorkerDetail = true }
        }
        .onChange(of: showWorkerDetail) { _, shown in
            if !shown { appState.swarmSelectedWorker = nil }
        }
    }

    private var healthBar: some View {
        HStack(spacing: 16) {
            if let health = appState.swarmHealth {
                SwarmHealthChip(
                    label: "\(health.workersOnline)/\(health.workersTotal) workers online",
                    color: health.workersOnline == health.workersTotal ? .green : .yellow,
                    icon: "person.3.fill"
                )
                SwarmHealthChip(
                    label: "\(health.missionsRunning) missions running",
                    color: health.missionsRunning > 0 ? HermesTheme.aresPrimary : .secondary,
                    icon: "arrow.triangle.2.circlepath"
                )
                if let load = health.systemLoad {
                    SwarmHealthChip(
                        label: String(format: "Load %.1f%%", load * 100),
                        color: load > 0.8 ? .red : load > 0.5 ? .orange : .green,
                        icon: "cpu"
                    )
                }
            } else if appState.isLoadingSwarm {
                ProgressView().scaleEffect(0.7)
                Text("Loading health…").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var workerGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 14)]
        return LazyVGrid(columns: columns, spacing: 14) {
            ForEach(appState.swarmWorkers) { worker in
                SwarmWorkerCard(worker: worker) {
                    appState.swarmSelectedWorker = worker
                }
            }
        }
    }
}

// MARK: - Health Chip

struct SwarmHealthChip: View {
    let label: String
    let color: Color
    let icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Worker Card

struct SwarmWorkerCard: View {
    let worker: SwarmWorker
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 9, height: 9)
                    Text(worker.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(worker.role)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(HermesTheme.insetFill, in: RoundedRectangle(cornerRadius: 6))
                }

                if let mission = worker.currentMission {
                    Text(mission)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                } else {
                    Text(worker.status == "offline" ? "Offline" : "Idle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let tokens = worker.tokenCount {
                    HStack(spacing: 4) {
                        Image(systemName: "number")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(tokenCountLabel(tokens))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HermesTheme.panelFill, in: RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                    .strokeBorder(HermesTheme.subtleStroke)
            )
        }
        .buttonStyle(.plain)
    }

    private var statusColor: Color {
        switch worker.status {
        case "active": return .green
        case "idle": return .yellow
        default: return Color.secondary.opacity(0.5)
        }
    }

    private func tokenCountLabel(_ count: Int) -> String {
        if count >= 1_000_000 { return String(format: "%.1fM tok", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.0fK tok", Double(count) / 1_000) }
        return "\(count) tok"
    }
}

// MARK: - Dispatch Sheet

struct SwarmDispatchSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedWorker: String = ""
    @State private var prompt: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Dispatch Mission")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Worker")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Worker", selection: $selectedWorker) {
                    Text("Any").tag("")
                    ForEach(appState.swarmWorkers) { worker in
                        Text(worker.name).tag(worker.id)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Prompt")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextEditor(text: $prompt)
                    .font(.body)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(HermesTheme.insetFill, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Dispatch") {
                    let workerName = appState.swarmWorkers.first(where: { $0.id == selectedWorker })?.name ?? selectedWorker
                    Task {
                        await appState.dispatchToSwarm(worker: workerName, prompt: prompt)
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            selectedWorker = appState.swarmWorkers.first?.id ?? ""
        }
    }
}

// MARK: - Worker Detail Sheet

struct SwarmWorkerDetailSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let worker: SwarmWorker
    @State private var chatMessage: String = ""
    @State private var isSending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(worker.name)
                        .font(.title2.weight(.semibold))
                    Text(worker.role)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                Text(worker.status.capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let mission = worker.currentMission {
                HermesSurfacePanel {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Current Mission")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(mission)
                            .font(.body)
                    }
                    .padding(12)
                }
            }

            let files = appState.swarmMemoryFiles.filter { $0.worker == worker.name }
            if !files.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Memory Files")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(files) { file in
                        HStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(file.filename)
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Direct Chat")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("Send a message to \(worker.name)…", text: $chatMessage)
                        .textFieldStyle(.plain)
                        .padding(10)
                        .background(HermesTheme.insetFill, in: RoundedRectangle(cornerRadius: 8))

                    Button {
                        sendDirectChat()
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(chatMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSending)
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 480)
        .task {
            await appState.loadSwarmMemory()
        }
    }

    private var statusColor: Color {
        switch worker.status {
        case "active": return .green
        case "idle": return .yellow
        default: return Color.secondary.opacity(0.5)
        }
    }

    private func sendDirectChat() {
        let msg = chatMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty else { return }
        isSending = true
        chatMessage = ""
        Task {
            await appState.sendSwarmDirectChat(worker: worker.name, message: msg)
            isSending = false
        }
    }
}
