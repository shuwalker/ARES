import SwiftUI

struct ARESRootView: View {
    @EnvironmentObject private var appState: ARESAppState

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 200)
                .background(ARESColors.surface)
        } detail: {
            switch appState.selectedTab {
            case .companion:
                CompanionView()
            case .office:
                OfficeView()
            case .hub:
                HubView()
            }
        }
        .background(ARESColors.background)
        .onAppear {
            appState.loadSelfModel()
            appState.refreshLiveStats()
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Brand
            VStack(spacing: 6) {
                Image(systemName: "shield.righthalf.filled")
                    .font(.system(size: 28))
                    .foregroundStyle(ARESColors.gold)

                Text("ARES")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(ARESColors.textPrimary)
                    .tracking(4)

                Rectangle()
                    .fill(ARESColors.gold)
                    .frame(width: 24, height: 1)
                    .padding(.top, 2)
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()
                .background(ARESColors.divider)

            // Tabs
            List(ARESTab.allCases, selection: $appState.selectedTab) { tab in
                Label {
                    Text(tab.title.uppercased())
                        .font(.caption)
                        .fontWeight(.medium)
                        .tracking(1.5)
                } icon: {
                    Image(systemName: tab.systemImage)
                        .font(.caption)
                }
                .foregroundStyle(appState.selectedTab == tab ? ARESColors.gold : ARESColors.textSecondary)
                .tag(tab)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(ARESColors.surface)

            Spacer()

            // Health dot
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.hermesRunning ? ARESColors.green : ARESColors.red)
                    .frame(width: 6, height: 6)
                Text(appState.hermesRunning ? "CONNECTED" : "OFFLINE")
                    .font(.system(size: 8))
                    .fontWeight(.bold)
                    .tracking(1.5)
                    .foregroundStyle(appState.hermesRunning ? ARESColors.green : ARESColors.red)
            }
            .padding(.bottom, 16)
        }
        .background(ARESColors.surface)
    }
}
