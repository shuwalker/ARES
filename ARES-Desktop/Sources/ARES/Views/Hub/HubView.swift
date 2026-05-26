import SwiftUI
import WebKit

struct HubView: View {
    @StateObject private var dodoState = AppState()
    @State private var hubSection: HubSection = .hermesDesktop

    var body: some View {
        VStack(spacing: 0) {
            // Hub nav bar
            HStack(spacing: 0) {
                ForEach(HubSection.allCases) { section in
                    Button {
                        hubSection = section
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: section.systemImage)
                                .font(.caption)
                            Text(section.title.uppercased())
                                .font(.system(size: 10))
                                .fontWeight(.bold)
                                .tracking(1.5)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(hubSection == section ? ARESColors.gold : ARESColors.textTertiary)
                    .background(
                        hubSection == section
                            ? ARESColors.gold.opacity(0.08)
                            : Color.clear
                    )
                    .overlay(alignment: .bottom) {
                        if hubSection == section {
                            Rectangle()
                                .fill(ARESColors.gold)
                                .frame(height: 2)
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
            .background(ARESColors.surface)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(ARESColors.divider)
                    .frame(height: 1)
            }

            // Content
            ZStack {
                switch hubSection {
                case .hermesDesktop:
                    NativeGuestHost(state: dodoState)
                case .webUI:
                    HermesWebUIView()
                case .settings:
                    HubSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(ARESColors.background)
    }
}

// MARK: - Dodo embed (contained NSHostingController)

struct NativeGuestHost: NSViewRepresentable {
    @ObservedObject var state: AppState

    func makeNSView(context: Context) -> NSView {
        let rootView = RootView().environmentObject(state)
        let controller = NSHostingController(rootView: rootView)
        context.coordinator.controller = controller

        controller.view.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(controller.view)

        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: container.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            controller.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])

        container.clipsToBounds = true
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var controller: AnyObject?
    }
}

// MARK: - Hermes WebUI view

struct HermesWebUIView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        if let url = URL(string: "http://localhost:9119") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Settings panel

struct HubSettingsView: View {
    @EnvironmentObject private var appState: ARESAppState
    @State private var statuses: [ARESDependency: DependencyStatus] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                // Integrations
                GroupBox {
                    VStack(spacing: 0) {
                        if statuses.isEmpty {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Scanning...")
                                    .font(.caption)
                                    .foregroundStyle(ARESColors.textSecondary)
                            }
                            .padding(.vertical, 12)
                        } else {
                            ForEach(Array(statuses.keys.sorted(by: { $0.rawValue < $1.rawValue })), id: \.self) { dep in
                                HStack(spacing: 10) {
                                    Image(systemName: iconFor(dep))
                                        .font(.caption)
                                        .foregroundStyle(colorFor(dep))
                                    Text(dep.name)
                                        .font(.subheadline)
                                        .foregroundStyle(ARESColors.textPrimary)
                                    Spacer()
                                    Text(labelFor(dep))
                                        .font(.caption)
                                        .foregroundStyle(colorFor(dep))
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 4)

                                if dep != Array(statuses.keys).last {
                                    Divider()
                                        .background(ARESColors.divider)
                                }
                            }
                        }
                    }
                    .padding(10)

                    HStack {
                        Spacer()
                        Button("RESCAN") {
                            Task { await scan() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(ARESColors.gold)
                    }
                } label: {
                    Text("INTEGRATIONS")
                        .font(.caption)
                        .fontWeight(.bold)
                        .tracking(2)
                        .foregroundStyle(ARESColors.textSecondary)
                }
                .groupBoxStyle(SpartanGroupBoxStyle())

                // Quick Launch
                GroupBox {
                    VStack(spacing: 0) {
                        appLinkRow("Hermes Dashboard", url: "http://localhost:9119", icon: "globe")
                        Divider().background(ARESColors.divider)
                        appLinkRow("SearXNG", url: "http://localhost:8080", icon: "magnifyingglass")
                        Divider().background(ARESColors.divider)
                        appLinkRow("Ollama", url: "http://localhost:11434", icon: "cpu.fill")
                        Divider().background(ARESColors.divider)
                        appLinkRow("Obsidian", appPath: "/Applications/Obsidian.app", icon: "note.text")
                    }
                } label: {
                    Text("QUICK LAUNCH")
                        .font(.caption)
                        .fontWeight(.bold)
                        .tracking(2)
                        .foregroundStyle(ARESColors.textSecondary)
                }
                .groupBoxStyle(SpartanGroupBoxStyle())

                // Status
                GroupBox {
                    VStack(spacing: 8) {
                        statusRow("Hermes", status: appState.hermesRunning)
                        statusRow("Skills", value: "\(appState.skillCount)")
                        statusRow("Sessions", value: "\(appState.sessionCount)")
                        statusRow("Memory", value: "\(appState.memoryPercent)%")
                    }
                    .padding(10)
                } label: {
                    Text("STATUS")
                        .font(.caption)
                        .fontWeight(.bold)
                        .tracking(2)
                        .foregroundStyle(ARESColors.textSecondary)
                }
                .groupBoxStyle(SpartanGroupBoxStyle())

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: 600)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ARESColors.background)
        .task { await scan() }
    }

    private func scan() async {
        let scanner = DependencyScanner()
        let results = await scanner.scanAll()
        var map: [ARESDependency: DependencyStatus] = [:]
        for r in results { map[r.dependency] = r.status }
        statuses = map
        appState.dependencies = map
    }

    private func statusRow(_ label: String, status: Bool? = nil, value: String? = nil) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(ARESColors.textSecondary)
            Spacer()
            if let status {
                Circle()
                    .fill(status ? Color.green : ARESColors.red)
                    .frame(width: 6, height: 6)
                Text(status ? "ONLINE" : "OFFLINE")
                    .font(.caption)
                    .fontWeight(.bold)
                    .tracking(1)
                    .foregroundStyle(status ? Color.green : ARESColors.red)
            } else if let value {
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(ARESColors.textPrimary)
            }
        }
    }

    private func appLinkRow(_ label: String, url: String? = nil, appPath: String? = nil, icon: String) -> some View {
        let exists: Bool = {
            if let path = appPath {
                return FileManager.default.fileExists(atPath: path)
            }
            return true // URLs just open
        }()

        return Button(action: {
            if let path = appPath {
                NSWorkspace.shared.open(URL(fileURLWithPath: path))
            } else if let urlStr = url, let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(exists ? ARESColors.textSecondary : ARESColors.textTertiary)
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(exists ? ARESColors.textPrimary : ARESColors.textTertiary)
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .font(.caption2)
                    .foregroundStyle(ARESColors.textTertiary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .disabled(!exists && appPath != nil)
    }

    private func iconFor(_ dep: ARESDependency) -> String {
        switch dep {
        case .dodoRepo: return "square.grid.2x2"
        case .hermesAgent: return "brain.fill"
        case .ollama: return "cpu.fill"
        case .searxng: return "magnifyingglass"
        }
    }

    private func labelFor(_ dep: ARESDependency) -> String {
        switch statuses[dep] {
        case .installed: return "OK"
        case .missing: return "MISSING"
        case .checking: return "..."
        case .failed(let m): return m
        case .none: return "—"
        }
    }

    private func colorFor(_ dep: ARESDependency) -> Color {
        switch statuses[dep] {
        case .installed: return .green
        case .missing: return ARESColors.red
        case .checking: return ARESColors.gold
        case .failed: return ARESColors.red
        case .none: return ARESColors.textTertiary
        }
    }
}

// MARK: - Spartan group box

struct SpartanGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label
            configuration.content
                .background(ARESColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(ARESColors.divider, lineWidth: 1)
                )
        }
    }
}

// MARK: - Hub section enum

enum HubSection: String, CaseIterable, Identifiable {
    case hermesDesktop, webUI, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hermesDesktop: return "Desktop"
        case .webUI: return "WebUI"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .hermesDesktop: return "square.grid.2x2"
        case .webUI: return "globe"
        case .settings: return "gearshape"
        }
    }
}
