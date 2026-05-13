import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var brain: BrainConnection
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ARES").font(.headline)
            Text(brain.agentState.rawValue.capitalized).font(.caption).foregroundColor(.secondary)
            Divider()
            Button("Show ARES") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.windows.first?.makeKeyAndOrderFront(nil)
            }
            ForEach(ImmersionLevel.allCases, id: \.self) { lvl in
                Button(lvl.label) { brain.immersionLevel = lvl }
            }
            Divider()
            Button("Quit") { NSApp.terminate(nil) }
        }
        .padding()
        .frame(width: 200)
    }
}