import SwiftUI

struct MenuBarView: View {
    @ObservedObject var daemon: ConsciousnessDaemon
    
    var body: some View {
        Group {
            Button("Hey ARES") {
                daemon.awaken()
            }
            .keyboardShortcut("A")
            
            Button("What's my schedule?") {
                daemon.querySchedule()
            }
            .keyboardShortcut("S")
            
            Divider()
            
            Button("Open Face Window") {
                openFaceWindow()
            }
            .keyboardShortcut("F")
            
            Button("Open Dashboard") {
                openDashboard()
            }
            .keyboardShortcut("D")
            
            Divider()
            
            Text(daemon.state.description)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Divider()
            
            Button("Settings...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .keyboardShortcut(",")
            
            Button("Quit") {
                daemon.shutdown()
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
    
    func openFaceWindow() {
        if let url = URL(string: "ares-mac://face-window") {
            NSWorkspace.shared.open(url)
        }
    }
    
    func openDashboard() {
        if let url = URL(string: "http://localhost:9119") {
            NSWorkspace.shared.open(url)
        }
    }
}
