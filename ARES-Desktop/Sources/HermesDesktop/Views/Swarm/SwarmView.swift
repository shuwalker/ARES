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
