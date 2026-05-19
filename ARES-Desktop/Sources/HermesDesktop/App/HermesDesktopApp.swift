import AppKit
import SwiftUI

@main
struct ARESApp: App {
    @NSApplicationDelegateAdaptor(HermesApplicationDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("ARES") {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 940, minHeight: 520)
                .background(HermesWindowTitleBarConfigurator())
        }
        .defaultSize(width: 1360, height: 860)
        .commands {
            ARESCommands(appState: appState)
        }
    }
}
