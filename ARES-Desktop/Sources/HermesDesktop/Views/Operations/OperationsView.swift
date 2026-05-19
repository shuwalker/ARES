import SwiftUI

struct OperationsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedTab: OperationsTab = .overview
    @State private var showAddAgentSheet = false
    @State private var agentToEdit: OperationsAgent?

    var body: some View {
        if !appState.dashboardAPIAvailable {
            ContentUnavailableView(
                "Dashboard Unavailable",
                systemImage: "building.2",
                description: Text("Connect to a local Hermes instance to view Operations.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HermesPageContainer(width: .dashboard) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    tabPicker
                    tabContent
                }
            }
            .task(id: appState.activeConnectionID) {
                await appState.loadOperations()
            }
            .sheet(isPresented: $showAddAgentSheet) {
                AddAgentSheet { name, role, profile in
                    Task { await appState.loadOperations() }
                }
            }
            .sheet(item: $agentToEdit) { agent in
                EditAgentSheet(agent: agent) {
                    Task { await appState.loadOperations() }
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HermesPageHeader(
            title: "Operations",
            subtitle: "Your persistent agent team — manage agents and review their outputs."
        )
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        Picker("View", selection: $selectedTab) {
            ForEach(OperationsTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 280)
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .overview:
            overviewContent
        case .outputs:
            outputsContent
        }
    }

    // MARK: - Overview

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            summaryStatsRow
            agentsList
        }
    }

    private var summaryStatsRow: some View {
        HStack(spacing: 16) {
            OperationsStatCard(
                label: "Agents",
                value: "\(appState.operationsAgents.count)",
                systemImage: "person.3"
            )
            OperationsStatCard(
                label: "Active Sessions",
                value: "\(appState.sessions.filter { $0.isRunning }.count)",
                systemImage: "clock.arrow.circlepath"
            )
            OperationsStatCard(
                label: "Scheduled Jobs",
                value: "\(appState.dashboardCronJobs.count)",
                systemImage: "calendar.badge.clock"
            )
            Spacer()
        }
    }

    @ViewBuilder
    private var agentsList: some View {
        HStack {
            Text("Agents")
                .font(.headline)
            Spacer()
            Button {
                showAddAgentSheet = true
            } label: {
                Label("Add Agent", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }

        if appState.isLoadingOperations {
            HermesLoadingState(label: "Loading agents…", minHeight: 200)
        } else if let error = appState.operationsError {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "Could not load agents",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        } else if appState.operationsAgents.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "No Agents Configured",
                    systemImage: "person.slash",
                    description: Text("Add agents to your workspace config to see them here.")
                )
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        } else {
            VStack(spacing: 8) {
                ForEach(appState.operationsAgents) { agent in
                    OperationsAgentRow(agent: agent, jobs: jobsForAgent(agent)) {
                        agentToEdit = agent
                    } onDelete: {
                        Task { await appState.loadOperations() }
                    }
                }
            }
        }
    }

    // MARK: - Outputs

    private var outputsContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Outputs")
                .font(.headline)

            if appState.sessions.isEmpty {
                HermesSurfacePanel {
                    ContentUnavailableView(
                        "No Recent Output",
                        systemImage: "tray",
                        description: Text("Session outputs will appear here as agents run.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 200)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(outputItems) { item in
                        OperationsOutputRow(item: item)
                        Divider().padding(.leading, 16)
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Helpers

    private func jobsForAgent(_ agent: OperationsAgent) -> Int {
        let profileName = agent.profile ?? agent.name
        return appState.dashboardCronJobs.filter { $0.profile == profileName }.count
    }

    private var outputItems: [OperationsOutputItem] {
        appState.sessions.prefix(50).map { session in
            OperationsOutputItem(
                id: session.id,
                agentName: session.source ?? "default",
                sessionID: session.id,
                lastMessage: session.preview ?? "",
                timestamp: session.lastActive?.dateValue
            )
        }
    }
}

// MARK: - Supporting Views

private struct OperationsStatCard: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 4) {
                Label(label, systemImage: systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.weight(.semibold))
            }
            .padding(14)
        }
        .frame(minWidth: 110)
    }
}

private struct OperationsAgentRow: View {
    let agent: OperationsAgent
    let jobs: Int
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HermesSurfacePanel {
            HStack(spacing: 14) {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 3) {
                    Text(agent.name)
                        .font(.headline)
                    if let role = agent.role, !role.isEmpty {
                        Text(role)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 3) {
                    if jobs > 0 {
                        Label("\(jobs) job\(jobs == 1 ? "" : "s")", systemImage: "calendar.badge.clock")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let profile = agent.profile, !profile.isEmpty {
                        Text(profile)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
            .contextMenu {
                Button("Edit") { onEdit() }
                Divider()
                Button("Delete", role: .destructive) { onDelete() }
            }
        }
    }
}

private struct OperationsOutputRow: View {
    let item: OperationsOutputItem

    var body: some View {
        HStack(spacing: 12) {
            Text(item.agentName)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.sessionID)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                if !item.lastMessage.isEmpty {
                    Text(item.lastMessage)
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let ts = item.timestamp {
                Text(ts, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
    }
}

// MARK: - Add Agent Sheet

private struct AddAgentSheet: View {
    let onSave: (String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var role = ""
    @State private var profile = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Add Agent")
                .font(.title2.weight(.semibold))

            LabeledContent("Name") {
                TextField("e.g. Builder", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("Role") {
                TextField("e.g. Software Engineer", text: $role)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("Profile") {
                TextField("e.g. default", text: $profile)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add Agent") {
                    onSave(name, role, profile)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

// MARK: - Edit Agent Sheet

private struct EditAgentSheet: View {
    let agent: OperationsAgent
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var role: String
    @State private var profile: String

    init(agent: OperationsAgent, onSave: @escaping () -> Void) {
        self.agent = agent
        self.onSave = onSave
        _name = State(initialValue: agent.name)
        _role = State(initialValue: agent.role ?? "")
        _profile = State(initialValue: agent.profile ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Edit Agent")
                .font(.title2.weight(.semibold))

            LabeledContent("Name") {
                TextField("Agent name", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("Role") {
                TextField("Agent role", text: $role)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("Profile") {
                TextField("Profile name", text: $profile)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

// MARK: - Data Models (local UI)

private enum OperationsTab: String, CaseIterable, Identifiable {
    case overview
    case outputs

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .outputs: "Outputs"
        }
    }
}

private struct OperationsOutputItem: Identifiable {
    let id: String
    let agentName: String
    let sessionID: String
    let lastMessage: String
    let timestamp: Date?
}
