import SwiftUI

@main
struct ARESApp: App {
    @StateObject private var brain = BrainConnection()
    @StateObject private var voice = VoiceManager()
    @StateObject private var activity = ActivityStore()
    @StateObject private var feeds = FeedStore()

    var body: some Scene {
        WindowGroup {
            ARESRootView()
                .environmentObject(brain)
                .environmentObject(voice)
                .environmentObject(activity)
                .environmentObject(feeds)
                .frame(minWidth: 900, minHeight: 650)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(CGSize(width: 1100, height: 750))
    }
}