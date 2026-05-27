import SwiftUI
import AppKit

@main
struct ARESApp: App {
    @StateObject private var appState: ARESAppState
    @StateObject private var samRuntime: SAMRuntime

    init() {
        let state = ARESAppState()
        _appState = StateObject(wrappedValue: state)
        _samRuntime = StateObject(wrappedValue: SAMRuntime(appState: state))
    }

    var body: some Scene {
        WindowGroup("ARES") {
            ARESRootView()
                .environmentObject(appState)
                .environmentObject(samRuntime)
                .environmentObject(samRuntime.conversationManager)
                .environmentObject(samRuntime.endpointManager)
                .environmentObject(samRuntime.sharedConversationService)
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
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About ARES") {}
            }
        }
    }
}
