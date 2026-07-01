import SwiftUI

// MARK: - Dashboard View
// Ties together task stats, AI engine status, recent activity, and system health
// into a single command-center overview.

struct DashboardView: View {
    @EnvironmentObject var state: AppState
    @StateObject private var taskManager = TaskManager.shared
    @State private var gatewayOnline: Bool? = nil
    @State private var ollamaOnline: Bool? = nil
    @State private var briefing: MorningBriefing?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                headerSection

                // Top row: Task summary + Engine status
                HStack(alignment: .top, spacing: 12) {
                    taskSummaryCard
                        .frame(maxWidth: .infinity)
                    engineStatusCard
                        .frame(maxWidth: .infinity)
                }

                // Middle row: Recent activity + Quick stats
                HStack(alignment: .top, spacing: 12) {
                    recentActivityCard
                        .frame(maxWidth: .infinity)
                    systemHealthCard
                        .frame(maxWidth: .infinity)
                }

                // Bottom: Today's plan preview (if briefing loaded)
                if let briefing = briefing {
                    todayPlanPreview(briefing)
                }
            }
            .padding()
        }
        .task {
            await loadAll()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dashboard")
                    .font(.title)
                    .fontWeight(.bold)
                Text(formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                Task { await loadAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
    }

    // MARK: - Task Summary Card

    private var taskSummaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Tasks", systemImage: "checklist")
                .font(.headline)

            HStack(spacing: 12) {
                DashboardStatBadge(
                    value: briefing?.todayCount ?? 0,
                    label: "Today",
                    color: .blue
                )
                DashboardStatBadge(
                    value: briefing?.overdueCount ?? 0,
                    label: "Overdue",
                    color: .red
                )
                DashboardStatBadge(
                    value: briefing?.inboxCount ?? 0,
                    label: "Inbox",
                    color: .orange
                )
                DashboardStatBadge(
                    value: briefing?.eventCount ?? 0,
                    label: "Events",
                    color: .green
                )
            }

            if let b = briefing, !b.bigTasks.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Next Up")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(b.bigTasks.first?.title ?? "—")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Engine Status Card

    private var engineStatusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("AI Engines", systemImage: "cpu")
                .font(.headline)

            ForEach(state.router.availableEngines, id: \.self) { engineId in
                HStack {
                    Circle()
                        .fill(engineId == state.activeEngine ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                    Text(engineDisplayName(engineId))
                        .font(.subheadline)
                    Spacer()
                    if engineId == state.activeEngine {
                        Text("ACTIVE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.accentColor)
                    }
                }
            }

            if state.router.availableEngines.isEmpty {
                Text("No engines registered")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Recent Activity Card

    private var recentActivityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Recent Activity", systemImage: "clock")
                .font(.headline)

            if state.messages.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "message")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No conversations yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                let recent = Array(state.messages.suffix(4))
                ForEach(recent) { msg in
                    HStack(spacing: 8) {
                        Image(systemName: msg.role == "user" ? "person.fill" : "sparkles")
                            .font(.caption2)
                            .foregroundColor(msg.role == "user" ? .blue : .accentColor)
                        Text(msg.content.prefix(50).trimmingCharacters(in: .whitespaces) + (msg.content.count > 50 ? "…" : ""))
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                    }
                }

                Divider()
                HStack {
                    Text("\(state.messages.count) total messages")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("via \(state.activeEngine)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - System Health Card

    private var systemHealthCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("System Health", systemImage: "heart.text.square")
                .font(.headline)

            healthRow("Hermes Gateway", status: gatewayOnline)
            healthRow("Ollama (local)", status: ollamaOnline)
            healthRow("Speech Service", status: state.isListening ? .some(true) : nil)
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    private func healthRow(_ name: String, status: Bool?) -> some View {
        HStack {
            Circle()
                .fill(status == true ? Color.green : status == false ? Color.red : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)
            Text(name)
                .font(.subheadline)
            Spacer()
            Text(status == true ? "Online" : status == false ? "Offline" : "Checking…")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Today's Plan Preview

    private func todayPlanPreview(_ b: MorningBriefing) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Today's Plan", systemImage: "list.bullet.rectangle")
                .font(.headline)

            if !b.bigTasks.isEmpty {
                ForEach(b.bigTasks) { task in
                    DashboardTaskRow(task: task, color: .red, label: "BIG")
                }
            }
            if !b.mediumTasks.isEmpty {
                ForEach(b.mediumTasks) { task in
                    DashboardTaskRow(task: task, color: .orange, label: "MED")
                }
            }
            if !b.smallTasks.isEmpty {
                ForEach(b.smallTasks.prefix(3)) { task in
                    DashboardTaskRow(task: task, color: .green, label: "SML")
                }
            }

            if b.bigTasks.isEmpty && b.mediumTasks.isEmpty && b.smallTasks.isEmpty {
                Text("No tasks scheduled for today")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.controlBackgroundColor))
        .cornerRadius(12)
    }

    // MARK: - Helpers

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d • HH:mm"
        return formatter.string(from: Date())
    }

    private func engineDisplayName(_ id: String) -> String {
        switch id.lowercased() {
        case "hermes": return "Hermes Agent"
        case "claude-cli": return "Claude Code CLI"
        case "claude": return "Claude (Anthropic)"
        case "gemini": return "Google Gemini"
        case "local": return "Local (Ollama)"
        default: return id.capitalized
        }
    }

    private func loadAll() async {
        // Load briefing
        briefing = await taskManager.generateMorningBriefing()

        // Check gateway
        gatewayOnline = (try? await state.gateway.health()) ?? false

        // Check Ollama
        let ollamaURL = URL(string: "http://localhost:11434/api/tags")!
        ollamaOnline = ((try? await URLSession.shared.data(from: ollamaURL)).map {
            ($0.1 as? HTTPURLResponse)?.statusCode == 200
        } ?? false)
    }
}

// MARK: - Supporting Components

struct DashboardStatBadge: View {
    let value: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(minWidth: 45)
        .padding(6)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
}

struct DashboardTaskRow: View {
    let task: ARESTask
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(color)
                .frame(width: 32, alignment: .leading)
            Text(task.title)
                .font(.subheadline)
            Spacer()
            Text(task.list)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }
}