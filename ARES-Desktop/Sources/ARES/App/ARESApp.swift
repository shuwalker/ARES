import SwiftUI
import AppKit
import ARESCore

@MainActor
@main
struct ARESApp: App {
    @NSApplicationDelegateAdaptor(ARESAppDelegate.self) var appDelegate

    @StateObject private var appState: ARESAppState

    init() {
        _appState = StateObject(wrappedValue: ARESRuntime.appState)
    }

    var body: some Scene {
        WindowGroup {
            ARESRootView()
                .environmentObject(appState)
                .frame(minWidth: 1024, minHeight: 600)
                .preferredColorScheme(.dark)
                .onAppear {
                    // Force window key for keyboard focus
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About ARES") {}
            }
        }
    }
}
