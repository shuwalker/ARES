import SwiftUI

@main
struct ARESApp: App {
    @StateObject private var appState = ARESAppState()

    var body: some Scene {
        WindowGroup("ARES") {
            if appState.hasBootstrapped {
                ARESRootView()
                    .environmentObject(appState)
                    .frame(minWidth: 940, minHeight: 520)
            } else {
                BootstrapView()
                    .environmentObject(appState)
                    .frame(width: 600, height: 480)
            }
        }
        .defaultSize(width: 1360, height: 860)
        .windowResizability(.contentSize)
    }
}
