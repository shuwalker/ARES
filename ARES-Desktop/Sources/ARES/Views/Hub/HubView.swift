import SwiftUI
import WebKit

struct HubView: View {
    @StateObject private var dodoState = AppState()
    @State private var hubSection: HubSection = .webUI

    var body: some View {
        VStack(spacing: 0) {
            // ARES Hub Top Bar - The "Skin"
            HStack(spacing: 1) {
                ForEach(HubSection.allCases) { section in
                    Button {
                        hubSection = section
                    } label: {
                        Label(section.title, systemImage: section.systemImage)
                            .font(.caption)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(hubSection == section ? .primary : .secondary)
                    .background(
                        hubSection == section
                            ? AnyShapeStyle(.ultraThinMaterial)
                            : AnyShapeStyle(.clear)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
            .padding(.bottom, 0)

            // Guest Host Area
            ZStack {
                switch hubSection {
                case .webUI:
                    HermesWebUIView()
                case .settings:
                    HubSettingsView()
                case .hermesDesktop:
                    NativeGuestHost(state: dodoState)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(.regularMaterial)
    }
}

// The "Wrapper" - Isolates the guest app in its own NSHostingController
struct NativeGuestHost: NSViewRepresentable {
    @ObservedObject var state: AppState

    func makeNSView(context: Context) -> NSView {
        let rootView = RootView().environmentObject(state)
        let controller = NSHostingController(rootView: rootView)
        
        // Retain the controller so it doesn't get deallocated
        context.coordinator.controller = controller
        
        // Pin the hosted view to fill this container exactly
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        
        // Wrap in a plain NSView that will enforce bounds
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(controller.view)
        
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: container.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            controller.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        
        // Clip any overflow
        container.clipsToBounds = true
        
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Handle state updates if necessary
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var controller: AnyObject?
    }
}

// MARK: - Hermes WebUI tab
struct HermesWebUIView: NSViewRepresentable {
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero,
                                configuration: WKWebViewConfiguration())
        if let url = URL(string: "http://localhost:9119") {
            webView.load(URLRequest(url: url))
        }
        return webView
    }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

// MARK: - Settings tab
struct HubSettingsView: View {
    @EnvironmentObject private var appState: ARESAppState
    @State private var statuses: [ARESDependency: DependencyStatus] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GroupBox("Integrations") {
                    VStack(spacing: 8) {
                        if statuses.isEmpty {
                            HStack {
                                ProgressView().controlSize(.small)
                                Text("Scanning...").font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(ARESDependency.allCases) { dep in
                                HStack {
                                    Label(dep.name, systemImage: iconFor(dep))
                                    Spacer()
                                    Text(labelFor(dep))
                                        .font(.caption)
                                        .foregroundStyle(colorFor(dep))
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .padding(8)

                    HStack {
                        Spacer()
                        Button("Rescan") { Task { await scan() } }
                            .buttonStyle(.bordered).controlSize(.small)
                    }
                }

                GroupBox("Quick Launch") {
                    VStack(spacing: 8) {
                        AppLink("Hermes Dashboard", url: "http://localhost:9119", exists: true)
                        if pathExists("/Applications/Obsidian.app") {
                            AppLink("Obsidian", path: "/Applications/Obsidian.app")
                        }
                        if pathExists("/Applications/DaVinci Resolve.app") {
                            AppLink("DaVinci Resolve", path: "/Applications/DaVinci Resolve.app")
                        }
                        AppLink("SearXNG", url: "http://localhost:8080",
                                exists: statuses[.searxng] == .installed)
                        AppLink("Ollama", url: "http://localhost:11434",
                                exists: statuses[.ollama] == .installed)
                    }
                    .padding(8)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func iconFor(_ dep: ARESDependency) -> String {
        switch dep {
        case .dodoRepo: "square.grid.2x2"
        case .hermesAgent: "brain.fill"
        case .ollama: "cpu.fill"
        case .searxng: "magnifyingglass"
        }
    }

    private func labelFor(_ dep: ARESDependency) -> String {
        switch statuses[dep] {
        case .installed: "Succeeded"
        case .missing: "Not found"
        case .checking: "Checking..."
        case .failed(let m): m
        case .none: "—"
        }
    }

    private func colorFor(_ dep: ARESDependency) -> Color {
        switch statuses[dep] {
        case .installed: .green
        case .missing: .secondary
        case .checking: .blue
        case .failed: .red
        case .none: .secondary
        }
    }

    private func pathExists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

struct AppLink: View {
    let label: String
    var path: String?
    var url: String?
    var exists: Bool

    init(_ label: String, path: String, exists: Bool = true) {
        self.label = label; self.path = path; self.exists = exists
    }

    init(_ label: String, url: String, exists: Bool = true) {
        self.label = label; self.url = url; self.exists = exists
    }

    var body: some View {
        if exists {
            Button(action: launch) {
                Label(label, systemImage: "arrow.up.forward.app")
            }
            .buttonStyle(.bordered).controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func launch() {
        if let path {
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
        } else if let urlStr = url, let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }
}

enum HubSection: String, CaseIterable, Identifiable {
    case hermesDesktop, webUI, settings
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hermesDesktop: "Hermes Desktop"
        case .webUI: "WebUI"
        case .settings: "Settings"
        }
    }
    var systemImage: String {
        switch self {
        case .hermesDesktop: "square.grid.2x2"
        case .webUI: "globe"
        case .settings: "gearshape"
        }
    }
}
