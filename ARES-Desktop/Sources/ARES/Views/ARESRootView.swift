import SwiftUI

struct ARESRootView: View {
    @EnvironmentObject private var appState: ARESAppState

    var body: some View {
        GeometryReader { proxy in
            let isNarrow = proxy.size.width < 760
            let sidebarWidth: CGFloat = isNarrow ? 64 : 180
            NavigationSplitView {
                sidebar(isNarrow: isNarrow)
                    .navigationSplitViewColumnWidth(min: sidebarWidth, ideal: sidebarWidth, max: sidebarWidth)
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
    }

    // MARK: - Sidebar

    private func sidebar(isNarrow: Bool) -> some View {
        VStack(spacing: 0) {
            // Brand
            VStack(spacing: 6) {
                Image(systemName: "shield.righthalf.filled")
                    .font(.system(size: 28))
                    .foregroundStyle(ARESColors.gold)

                if !isNarrow {
                    Text("ARES")
                        .font(.system(size: 18, weight: .bold, design: .serif))
                        .foregroundStyle(ARESColors.textPrimary)
                        .tracking(4)

                    Rectangle()
                        .fill(ARESColors.gold)
                        .frame(width: 24, height: 1)
                        .padding(.top, 2)
                }
            }
            .padding(.top, 24)
            .padding(.bottom, 20)

            Divider()
                .background(ARESColors.divider)

            // Tabs
            List(ARESTab.allCases, selection: $appState.selectedTab) { tab in
                Label {
                    if !isNarrow {
                        Text(tab.title.uppercased())
                            .font(.caption)
                            .fontWeight(.medium)
                            .tracking(1.5)
                    }
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
                if !isNarrow {
                    Text(appState.hermesRunning ? "CONNECTED" : "OFFLINE")
                        .font(.system(size: 8))
                        .fontWeight(.bold)
                        .tracking(1.5)
                        .foregroundStyle(appState.hermesRunning ? ARESColors.green : ARESColors.red)
                }
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(ARESColors.surface)
    }
}
