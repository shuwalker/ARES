import SwiftUI
import AppKit

@main
struct ARESApp: App {
    @StateObject private var appState = ARESAppState()

    var body: some Scene {
        WindowGroup("ARES") {
            ARESRootView()
                .environmentObject(appState)
                .frame(minWidth: 1024, minHeight: 600)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1440, height: 900)
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About ARES") {}
            }
        }
    }
}
