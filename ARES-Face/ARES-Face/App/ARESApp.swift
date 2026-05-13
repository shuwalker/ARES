import SwiftUI

@main
struct ARESApp: App {
    @StateObject private var brain = BrainConnection()
    @StateObject private var voice = VoiceManager()
    
    var body: some Scene {
        WindowGroup {
            ARESRootView()
                .environmentObject(brain)
                .environmentObject(voice)
                .frame(minWidth: 900, minHeight: 650)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(CGSize(width: 1100, height: 750))
        
        MenuBarExtra("ARES", systemImage: "circle.hexagonpath") {
            MenuBarView()
                .environmentObject(brain)
        }
    }
}