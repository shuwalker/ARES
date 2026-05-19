import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Mode

private enum SwarmViewMode: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case runtime = "Runtime"
    case kanban = "Kanban"
    case reports = "Reports"

    var id: String { rawValue }
}

// MARK: - Root View

struct SwarmView: View {
    @EnvironmentObject private var appState: AppState
    @State private var mode: SwarmViewMode = .overview

    var body: some View {
        if !appState.dashboardAPIAvailable {
            ContentUnavailableView(
                "Swarm requires SSH connection",
                systemImage: "person.3.fill",
                description: Text("Connect to a host with the Hermes dashboard to access the Swarm digital office.")
            )
        } else {
            VStack(spacing: 0) {
                modeContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Mode", selection: $mode) {
                        ForEach(SwarmViewMode.allCases) { m in
                            Text(m.rawValue).tag(m)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 360)
                }
            }
            .task(id: appState.activeConnectionID) {
                await appState.loadSwarm()
                await appState.loadSwarmKanban()
                await appState.loadSwarmReports()
            }
            .onChange(of: mode) { _, newMode in
                if newMode == .overview || newMode == .reports {
                    appState.startSwarmPolling()
                    appState.stopSwarmRuntimePolling()
                } else if newMode == .runtime {
                    appState.stopSwarmPolling()
                    appState.startSwarmRuntimePolling()
                } else {
                    appState.stopSwarmPolling()
                    appState.stopSwarmRuntimePolling()
                }
            }
            .onAppear {
                appState.startSwarmPolling()
            }
            .onDisappear {
                appState.stopSwarmPolling()
                appState.stopSwarmRuntimePolling()
            }
        }
    }

    @ViewBuilder
    private var modeContent: some View {
        switch mode {
        case .overview:
            SwarmOverviewView()
        case .runtime:
            SwarmRuntimeView()
        case .kanban:
            SwarmKanbanView()
        case .reports:
            SwarmReportsView()
        }
    }
}

// MARK: - Overview

private struct SwarmOverviewView: View {
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

private struct SwarmHealthChip: View {
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

private struct SwarmWorkerCard: View {
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

private struct SwarmDispatchSheet: View {
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

private struct SwarmWorkerDetailSheet: View {
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

// MARK: - Runtime View

private struct SwarmRuntimeView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HSplitView {
            workerList
                .frame(minWidth: 180, idealWidth: 220, maxWidth: 280)

            terminalPane
                .frame(minWidth: 320, maxWidth: .infinity)
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

private struct SwarmTerminalView: View {
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

// MARK: - Kanban View

private enum SwarmKanbanColumn: String, CaseIterable {
    case backlog = "backlog"
    case ready = "ready"
    case running = "running"
    case review = "review"
    case blocked = "blocked"
    case done = "done"

    var displayName: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .backlog: return .secondary
        case .ready: return .blue
        case .running: return HermesTheme.aresPrimary
        case .review: return .orange
        case .blocked: return .red
        case .done: return .green
        }
    }
}

private struct SwarmKanbanView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showNewCardSheet = false
    @State private var draggingCard: SwarmKanbanCard?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Swarm Kanban")
                    .font(.title3.weight(.semibold))
                    .padding(.leading, 20)
                Spacer()
                Button {
                    showNewCardSheet = true
                } label: {
                    Label("New Card", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .padding(.trailing, 20)
            }
            .padding(.vertical, 14)

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(SwarmKanbanColumn.allCases, id: \.rawValue) { col in
                        SwarmKanbanColumnView(
                            column: col,
                            cards: appState.swarmKanbanCards.filter { $0.column == col.rawValue },
                            draggingCard: $draggingCard
                        ) { card, targetColumn in
                            Task { await appState.moveSwarmKanbanCard(card, toColumn: targetColumn) }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: appState.activeConnectionID) {
            await appState.loadSwarmKanban()
        }
        .sheet(isPresented: $showNewCardSheet) {
            SwarmNewCardSheet()
        }
    }
}

private struct SwarmKanbanColumnView: View {
    let column: SwarmKanbanColumn
    let cards: [SwarmKanbanCard]
    @Binding var draggingCard: SwarmKanbanCard?
    let onDrop: (SwarmKanbanCard, String) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Circle()
                    .fill(column.color)
                    .frame(width: 8, height: 8)
                Text(column.displayName)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(cards.count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(cards) { card in
                SwarmKanbanCardView(card: card)
                    .onDrag {
                        draggingCard = card
                        return NSItemProvider(object: card.id as NSString)
                    }
            }

            if cards.isEmpty {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.clear)
                    .frame(height: 60)
                    .overlay(
                        Text("Drop here")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    )
            }

            Spacer()
        }
        .padding(12)
        .frame(width: 220, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: HermesTheme.insetCornerRadius, style: .continuous)
                .fill(isDropTargeted ? column.color.opacity(0.12) : HermesTheme.insetFill)
        )
        .onDrop(of: [UTType.plainText], isTargeted: $isDropTargeted) { providers in
            guard let dragging = draggingCard else { return false }
            onDrop(dragging, column.rawValue)
            draggingCard = nil
            return true
        }
    }
}

private struct SwarmKanbanCardView: View {
    let card: SwarmKanbanCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(card.title)
                .font(.caption.weight(.medium))
                .lineLimit(3)

            HStack(spacing: 6) {
                if let worker = card.worker {
                    Text(worker)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let priority = card.priority {
                    priorityBadge(priority)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HermesTheme.panelFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(HermesTheme.subtleStroke)
        )
    }

    private func priorityBadge(_ priority: String) -> some View {
        let color: Color = {
            switch priority.lowercased() {
            case "high", "urgent": return .red
            case "medium", "normal": return .orange
            default: return .secondary
            }
        }()
        return Text(priority.capitalized)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct SwarmNewCardSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var worker = ""
    @State private var priority = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Kanban Card")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Card title…", text: $title)
                    .textFieldStyle(.plain)
                    .padding(10)
                    .background(HermesTheme.insetFill, in: RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Assign Worker (optional)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Worker", selection: $worker) {
                    Text("Unassigned").tag("")
                    ForEach(appState.swarmWorkers) { w in
                        Text(w.name).tag(w.name)
                    }
                }
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Priority (optional)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Picker("Priority", selection: $priority) {
                    Text("None").tag("")
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                    Text("High").tag("high")
                    Text("Urgent").tag("urgent")
                }
                .labelsHidden()
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create") {
                    Task {
                        await appState.createSwarmKanbanCard(
                            title: title,
                            worker: worker.isEmpty ? nil : worker,
                            priority: priority.isEmpty ? nil : priority
                        )
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 400)
    }
}

// MARK: - Reports View

private enum SwarmReportFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case needsReview = "Needs Review"
    case blocked = "Blocked"
    case done = "Done"

    var id: String { rawValue }
}

private struct SwarmReportsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var filter: SwarmReportFilter = .all

    private var filtered: [SwarmReport] {
        switch filter {
        case .all: return appState.swarmReports
        case .needsReview: return appState.swarmReports.filter { $0.status == "needs_review" }
        case .blocked: return appState.swarmReports.filter { $0.status == "blocked" }
        case .done: return appState.swarmReports.filter { $0.status == "done" }
        }
    }

    var body: some View {
        HermesPageContainer {
            VStack(alignment: .leading, spacing: 18) {
                HermesPageHeader(
                    title: "Mission Reports",
                    subtitle: "Aggregated mission results from all swarm workers."
                )

                Picker("Filter", selection: $filter) {
                    ForEach(SwarmReportFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 480)

                if appState.swarmReports.isEmpty {
                    ContentUnavailableView(
                        "No Reports",
                        systemImage: "doc.text",
                        description: Text("Mission reports will appear here when workers complete tasks.")
                    )
                } else if filtered.isEmpty {
                    ContentUnavailableView(
                        "No Matching Reports",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("No reports match the selected filter.")
                    )
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { report in
                            SwarmReportRow(report: report)
                        }
                    }
                }
            }
        }
        .task(id: appState.activeConnectionID) {
            await appState.loadSwarmReports()
        }
    }
}

private struct SwarmReportRow: View {
    let report: SwarmReport

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(report.missionTitle)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: "person.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(report.worker)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let date = report.createdAt {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(date)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let summary = report.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            reportBadge
        }
        .padding(14)
        .background(HermesTheme.panelFill, in: RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .strokeBorder(HermesTheme.subtleStroke)
        )
    }

    private var reportBadge: some View {
        let (label, color): (String, Color) = {
            switch report.status {
            case "needs_review": return ("Needs Review", .orange)
            case "ready_to_merge": return ("Ready to Merge", .green)
            case "blocked": return ("Blocked", .red)
            case "done": return ("Done", Color(NSColor.systemGreen))
            default: return (report.status.replacingOccurrences(of: "_", with: " ").capitalized, .secondary)
            }
        }()
        return Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

