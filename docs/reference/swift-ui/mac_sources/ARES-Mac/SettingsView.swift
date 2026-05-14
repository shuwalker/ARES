import SwiftUI

struct SettingsView: View {
    @ObservedObject var daemon: ConsciousnessDaemon
    
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            
            VoiceSettings()
                .tabItem { Label("Voice", systemImage: "waveform") }
            
            AboutSettings()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 400, height: 250)
    }
}

struct GeneralSettings: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = true
    @AppStorage("showFaceWindow") private var showFaceWindow = true
    
    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
            Toggle("Show face window", isOn: $showFaceWindow)
            Divider()
            Text("ARES-Mac v0.1")
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct VoiceSettings: View {
    @AppStorage("wakeWord") private var wakeWord = "Hey ARES"
    
    var body: some View {
        Form {
            TextField("Wake word", text: $wakeWord)
                .textFieldStyle(.roundedBorder)
            Text("Say this to wake ARES")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

struct AboutSettings: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)
            Text("ARES-Mac")
                .font(.title2)
                .bold()
            Text("Version 0.1 — Cradle")
                .foregroundColor(.secondary)
            Text("The persistent desk companion")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
