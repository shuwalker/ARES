import ARESCore
import SwiftUI

#if os(macOS)
import AppKit
#endif

/// Settings tab — Configuration that's actually needed.
///
/// Four sections per the product spec:
///   1. Integrations — which detected tools ARES is allowed to read from
///   2. Quick launch — system commands with one-tap buttons
///   3. Runtime status — model, provider, gateway health (read-only)
///   4. Diagnostics — "Run Check" button producing an inline report
struct SettingsView: View {
    @EnvironmentObject private var appState: ARESAppState
    @State private var integrations: [IntegrationToggle] = defaultIntegrations
    @State private var quickLaunchItems: [QuickLaunchItem] = defaultQuickLaunch
    @State private var diagnosticReport: String? = nil
    @State private var isRunningDiagnostics = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Section 1: Integrations
                settingsSection(header: "INTEGRATIONS",
                                subtitle: "Which detected tools ARES can read session data from") {
                    ForEach($integrations) { $item in
                        Toggle(item.name, isOn: $item.enabled)
                            .toggleStyle(.switch)
                            .foregroundStyle(ARESColors.textPrimary)
                    }
                }

                // Section 2: Quick launch
                settingsSection(header: "QUICK LAUNCH",
                                subtitle: "System commands you want one-tap access to") {
                    ForEach(quickLaunchItems) { item in
                        HStack {
                            Image(systemName: item.icon)
                                .foregroundStyle(ARESColors.gold)
                                .frame(width: 20)
                            Text(item.name)
                                .foregroundStyle(ARESColors.textPrimary)
                            Spacer()
                            Button("Open") {
                                #if os(macOS)
                                NSWorkspace.shared.open(URL(string: item.command)!)
                                #endif
                            }
                            .buttonStyle(.bordered)
                            .tint(ARESColors.gold.opacity(0.2))
                            .foregroundStyle(ARESColors.gold)
                        }
                    }
                }

                // Section 3: Runtime status (read-only)
                settingsSection(header: "RUNTIME STATUS",
                                subtitle: "Current ARES backend status — read-only") {
                    LabeledContent("Gateway URL", value: appState.hermesGatewayURL)
                    LabeledContent("Gateway", value: appState.hermesRunning ? "Connected" : "Offline")
                        .foregroundStyle(appState.hermesRunning ? ARESColors.green : ARESColors.red)
                    LabeledContent("Sessions loaded", value: "\(appState.sessionCount)")
                    LabeledContent("Skills loaded", value: "\(appState.skillCount)")
                    LabeledContent("Memory used", value: "\(appState.memoryPercent)%")
                }

                // Section 4: Diagnostics
                settingsSection(header: "DIAGNOSTICS",
                                subtitle: "Run a health check and view results in-place") {
                    Button(action: runDiagnostics) {
                        HStack {
                            Image(systemName: "stethoscope")
                            Text(isRunningDiagnostics ? "Checking..." : "Run Check")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(ARESColors.gold.opacity(0.2))
                    .foregroundStyle(ARESColors.gold)
                    .disabled(isRunningDiagnostics)

                    if let report = diagnosticReport {
                        Text(report)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(ARESColors.textSecondary)
                            .padding(8)
                            .background(ARESColors.background)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(20)
        }
        .background(ARESColors.background)
    }

    // MARK: - Helpers

    private func settingsSection<Content: View>(header: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(header)
                .font(.system(size: 11, weight: .bold))
                .tracking(2)
                .foregroundStyle(ARESColors.gold)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(ARESColors.textTertiary)
            VStack(alignment: .leading, spacing: 6) {
                content()
            }
            .padding(12)
            .background(ARESColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func runDiagnostics() {
        isRunningDiagnostics = true
        diagnosticReport = nil

        Task {
            var lines: [String] = []
            lines.append("=== ARES Diagnostics ===")
            lines.append("")

            // Check gateway reachable
            lines.append("Gateway URL: \(appState.hermesGatewayURL)")
            lines.append("Gateway: \(appState.hermesRunning ? "OK" : "UNREACHABLE")")

            // Check Ollama
            let ollamaURL = URL(string: "http://localhost:11434/api/tags")!
            var ollamaOK = false
            if let _ = try? await URLSession.shared.data(from: ollamaURL) {
                ollamaOK = true
            }
            lines.append("Ollama: \(ollamaOK ? "OK" : "UNREACHABLE")")

            // Check detected tools
            let registry = IntegrationRegistry()
            registry.scan()
            let detected = registry.detected
            lines.append("Detected tools: \(detected.map(\.name).joined(separator: ", "))")
            lines.append("ARES config: \(FileManager.default.fileExists(atPath: ARESEnvironment.defaultHomeDirectory.path) ? "OK" : "MISSING")")

            lines.append("")
            lines.append("=== Check complete ===")

            diagnosticReport = lines.joined(separator: "\n")
            isRunningDiagnostics = false
        }
    }
}

// MARK: - Data models

struct IntegrationToggle: Identifiable {
    let id: String
    let name: String
    var enabled: Bool
}

struct QuickLaunchItem: Identifiable {
    let id: String
    let name: String
    let icon: String
    let command: String  // URL scheme or shell command
}

// MARK: - Defaults

private let defaultIntegrations: [IntegrationToggle] = [
    IntegrationToggle(id: "hermes", name: "Hermes Agent", enabled: true),
    IntegrationToggle(id: "claude", name: "Claude Code", enabled: true),
    IntegrationToggle(id: "gemini", name: "Gemini CLI", enabled: true),
    IntegrationToggle(id: "odysseus", name: "Odysseus", enabled: true),
]

private let defaultQuickLaunch: [QuickLaunchItem] = [
    QuickLaunchItem(id: "terminal", name: "Terminal", icon: "terminal.fill", command: "x-man-page://"),
    QuickLaunchItem(id: "hermes-dashboard", name: "Hermes Dashboard", icon: "bolt.horizontal", command: "http://localhost:9119"),
]