import SwiftUI

/// Hermes config viewer. Reads from dashboard API.
struct ConfigView: View {
    @State private var config: Config?
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        ScrollView {
            if isLoading {
                ProgressView("Loading config...").padding()
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { loadConfig() }.buttonStyle(.bordered)
                }.padding()
            } else if let config = config {
                VStack(alignment: .leading, spacing: 16) {
                    // Agent section
                    GroupBox("Agent") {
                        if let agent = config.agent {
                            VStack(alignment: .leading, spacing: 4) {
                                KeyValueRow("Model", config.model ?? "—")
                                KeyValueRow("Max Turns", "\(agent.maxTurns ?? 90)")
                                KeyValueRow("Reasoning", agent.reasoningEffort ?? "—")
                                KeyValueRow("Verbose", "\(agent.verbose ?? false)")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    // Persona section
                    GroupBox("Personalities") {
                        if let personas = config.agent?.personalities {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(personas.keys.sorted()), id: \.self) { key in
                                    Text(key).font(.caption.weight(.medium))
                                    Text(personas[key] ?? "")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .padding(.vertical, 4)
                        } else {
                            Text("No personalities configured")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    
                    // Terminal section
                    GroupBox("Terminal") {
                        if let term = config.terminal {
                            VStack(alignment: .leading, spacing: 4) {
                                KeyValueRow("Backend", term.backend ?? "—")
                                KeyValueRow("Timeout", "\(term.timeout ?? 180)s")
                                KeyValueRow("CWD", term.cwd ?? "—")
                                KeyValueRow("Persistent Shell", "\(term.persistentShell ?? false)")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    
                    // Toolsets
                    GroupBox("Toolsets") {
                        if let tools = config.toolsets, !tools.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(tools, id: \.self) { t in
                                    Text(t).font(.caption)
                                }
                            }
                            .padding(.vertical, 4)
                        } else {
                            Text("No toolsets configured")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear { loadConfig() }
    }
    
    private func loadConfig() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                config = try await HermesDashboardService.shared.getConfig()
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }
}

struct KeyValueRow: View {
    let key: String
    let value: String
    
    init(_ key: String, _ value: String) {
        self.key = key
        self.value = value
    }
    
    var body: some View {
        HStack {
            Text(key).font(.caption).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            Text(value).font(.caption)
            Spacer()
        }
    }
}