import SwiftUI

struct OfficeView: View {
    @EnvironmentObject private var appState: ARESAppState

    var body: some View {
        VStack(spacing: 0) {
            if appState.officeAgents.isEmpty {
                emptyState
            } else {
                agentGrid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ARESColors.background)
        .onAppear {
            appState.refreshLiveStats()
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .stroke(ARESColors.gold.opacity(0.2), lineWidth: 1)
                    .frame(width: 100, height: 100)

                Image(systemName: "shield.righthalf.filled")
                    .font(.system(size: 36))
                    .foregroundStyle(ARESColors.gold.opacity(0.6))
            }

            Text("AGENT CREW")
                .font(.title2)
                .fontWeight(.bold)
                .tracking(4)
                .foregroundStyle(ARESColors.textPrimary)

            Text("No agents detected. Start Hermes to populate.")
                .font(.subheadline)
                .foregroundStyle(ARESColors.textSecondary)

            Button(action: { appState.refreshLiveStats() }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("SCAN")
                        .font(.caption)
                        .fontWeight(.bold)
                        .tracking(2)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
            }
            .buttonStyle(.bordered)
            .tint(ARESColors.gold)

            Spacer()
        }
    }

    // MARK: - Agent grid

    private var agentGrid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AGENT CREW")
                            .font(.caption)
                            .fontWeight(.bold)
                            .tracking(3)
                            .foregroundStyle(ARESColors.textSecondary)
                        Text("\(appState.officeAgentCount) agents online")
                            .font(.subheadline)
                            .foregroundStyle(ARESColors.textTertiary)
                    }
                    Spacer()
                    Button(action: { appState.refreshLiveStats() }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ARESColors.textSecondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)

                // Agent cards
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(appState.officeAgents) { agent in
                        AgentCardView(agent: agent)
                    }
                }
                .padding(.horizontal, 24)

                // Legend
                HStack(spacing: 24) {
                    StatusDot(color: .green, label: "ACTIVE")
                    StatusDot(color: .orange, label: "IDLE")
                    StatusDot(color: .gray, label: "OFFLINE")
                }
                .font(.caption2)
                .foregroundStyle(ARESColors.textTertiary)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

                Spacer()
            }
        }
    }
}

// MARK: - Agent card

struct AgentCardView: View {
    let agent: AgentCard

    var body: some View {
        VStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(agent.status.color.opacity(0.15))
                    .frame(width: 56, height: 56)

                Image(systemName: agentIcon)
                    .font(.title3)
                    .foregroundStyle(agent.status.color)

                // Status dot
                Circle()
                    .fill(agent.status.color)
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(ARESColors.background, lineWidth: 2)
                    )
                    .offset(x: 22, y: 22)
            }

            VStack(spacing: 2) {
                Text(agent.name)
                    .font(.headline)
                    .foregroundStyle(ARESColors.textPrimary)
                Text(agent.role)
                    .font(.caption)
                    .foregroundStyle(ARESColors.textSecondary)
            }

            Text(agent.detail)
                .font(.caption2)
                .foregroundStyle(ARESColors.textTertiary)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            // Status bar
            HStack(spacing: 4) {
                Circle()
                    .fill(agent.status.color)
                    .frame(width: 4, height: 4)
                Text(agent.status.label.uppercased())
                    .font(.system(size: 8))
                    .fontWeight(.bold)
                    .tracking(1.5)
                    .foregroundStyle(agent.status.color)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(agent.status.color.opacity(0.1))
            .clipShape(Capsule())
        }
        .padding(16)
        .background(ARESColors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(agent.status.color.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var agentIcon: String {
        switch agent.name.lowercased() {
        case "hermes": return "brain.head.profile.fill"
        case "ollama": return "cpu.fill"
        case "searxng": return "magnifyingglass"
        default: return "circle.grid.cross.fill"
        }
    }
}

// MARK: - Status dot legend

struct StatusDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(label)
                .tracking(1)
        }
    }
}
