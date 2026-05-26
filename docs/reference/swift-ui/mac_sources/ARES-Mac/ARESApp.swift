import SwiftUI

@main
struct ARESApp: App {
    @StateObject private var daemon = ConsciousnessDaemon()
    
    var body: some Scene {
        MenuBarExtra("ARES", systemImage: "person.circle.fill") {
            MenuBarView(daemon: daemon)
        }
        .menuBarExtraStyle(.menu)
        
        Window("ARES-Mac", id: "face-window") {
            FaceWindowView()
                .environmentObject(daemon)
                .frame(width: 200, height: 200)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 200, height: 200)
        .handlesExternalEvents(matching: Set(["face-window"]))
        
        Settings {
            SettingsView(daemon: daemon)
        }
    }
}
