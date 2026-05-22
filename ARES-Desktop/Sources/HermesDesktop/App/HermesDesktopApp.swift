import AppKit
import SwiftUI

@main
struct ARESApp: App {
    var body: some Scene {
        WindowGroup("ARES", id: "main") {
            ContentView()
                .frame(minWidth: 500, minHeight: 600)
        }
        .defaultSize(width: 800, height: 700)
    }
}
