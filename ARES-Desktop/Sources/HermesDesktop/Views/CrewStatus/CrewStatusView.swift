import SwiftUI

struct CrewStatusView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        if !appState.dashboardAPIAvailable {
            ContentUnavailableView(
                "Dashboard Unavailable",
                systemImage: "person.badge.shield.checkmark",
                description: Text("Connect to a local Hermes instance to view Crew Status.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            HermesPageContainer(width: .dashboard) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    crewGrid
                }
            }
            .task(id: appState.activeConnectionID) {
                await appState.loadCrewStatus()
                // Polling loop: auto-cancels when the view disappears or connection changes
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(30))
                    guard !Task.isCancelled else { break }
                    await appState.loadCrewStatus()
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HermesPageHeader(title: "Crew Status", subtitle: "Live health monitoring across all agents and profiles.") {
            Button {
                Task { await appState.loadCrewStatus() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(appState.isLoadingCrewStatus)
        }
    }

    // MARK: - Grid

    @ViewBuilder
    private var crewGrid: some View {
        if appState.isLoadingCrewStatus && appState.crewStatusEntries.isEmpty {
            HermesSurfacePanel {
                HermesLoadingState(label: "Loading crew status…", minHeight: 260)
            }
        } else if let error = appState.crewStatusError, appState.crewStatusEntries.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "Could not load crew status",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        } else if appState.crewStatusEntries.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    "No Agents Found",
                    systemImage: "person.slash",
                    description: Text("Configure profiles to see agent status here.")
                )
                .frame(maxWidth: .infinity, minHeight: 200)
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                ForEach(appState.crewStatusEntries) { entry in
                    CrewStatusCard(entry: entry) { section in
                        appState.requestSectionSelection(section)
                    }
                }
            }
        }
    }
}

// MARK: - Crew Status Card

private struct CrewStatusCard: View {
    let entry: CrewStatusEntry
    let navigateTo: (AppSection) -> Void

    var body: some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 14) {
                // Header row: avatar + name + status dot
                HStack(spacing: 10) {
                    avatarCircle
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.profileName)
                            .font(.headline)
                            .lineLimit(1)
                        statusLabel
                    }
                    Spacer()
                }

                Divider()

                // Stats grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    CrewStatItem(label: "Sessions", value: "\(entry.sessionCount)")
                    CrewStatItem(label: "Messages", value: "\(entry.messageCount)")
                    CrewStatItem(label: "Tokens", value: tokenDisplay)
                    CrewStatItem(label: "Est. Cost", value: costDisplay)
                    CrewStatItem(label: "Cron Jobs", value: "\(entry.cronJobCount)")
                }

                // Action buttons
                HStack(spacing: 8) {
                    Button {
                        navigateTo(.kanban)
                    } label: {
                        Label("Tasks", systemImage: "rectangle.3.group")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        navigateTo(.jobs)
                    } label: {
                        Label("Jobs", systemImage: "calendar.badge.clock")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(16)
        }
    }

    private var avatarCircle: some View {
        ZStack {
            Circle()
                .fill(avatarColor.opacity(0.15))
                .frame(width: 40, height: 40)
            Text(String(entry.profileName.prefix(1)).uppercased())
                .font(.title3.weight(.semibold))
                .foregroundStyle(avatarColor)
        }
    }

    private var statusLabel: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(entry.isOnline ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
            Text(entry.isOnline ? "Online" : "Offline")
                .font(.caption)
                .foregroundStyle(entry.isOnline ? .green : .secondary)
        }
    }

    private var avatarColor: Color {
        let colors: [Color] = [.blue, .purple, .indigo, .teal, .orange, .pink]
        let index = abs(entry.profileName.hashValue) % colors.count
        return colors[index]
    }

    private var tokenDisplay: String {
        if entry.tokenCount >= 1_000_000 {
            return String(format: "%.1fM", Double(entry.tokenCount) / 1_000_000)
        } else if entry.tokenCount >= 1_000 {
            return String(format: "%.1fK", Double(entry.tokenCount) / 1_000)
        }
        return "\(entry.tokenCount)"
    }

    private var costDisplay: String {
        if entry.estimatedCost == 0 {
            return "$0.00"
        }
        return String(format: "$%.4f", entry.estimatedCost)
    }
}

// MARK: - Stat Item

private struct CrewStatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline.weight(.semibold))
        }
    }
}
