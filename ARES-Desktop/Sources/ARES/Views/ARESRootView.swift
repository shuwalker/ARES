import SwiftUI

struct ARESRootView: View {
    @EnvironmentObject private var appState: ARESAppState

    var body: some View {
        NavigationSplitView {
            List(ARESTab.allCases, selection: $appState.selectedTab) { tab in
                Label(tab.title, systemImage: tab.systemImage)
                    .tag(tab)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 200)
            .listStyle(.sidebar)
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
        .navigationTitle(appState.selectedTab.title)
        .onAppear {
            appState.loadSelfModel()
        }
    }
}
