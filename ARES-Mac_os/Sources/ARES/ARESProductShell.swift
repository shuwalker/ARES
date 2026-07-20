import SwiftUI
import ARESCore

/// Product destinations shared conceptually with the WebUI navigation model.
/// Mac is the primary on-device product; WebUI is the remote/light client.
enum ARESDestination: String, CaseIterable, Identifiable, Hashable {
    case home
    case chat
    case today
    case connections
    case workspace
    case activity
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .chat: return "Chat"
        case .today: return "Today"
        case .connections: return "Connections"
        case .workspace: return "Workspace"
        case .activity: return "Activity"
        case .settings: return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .chat: return "bubble.left.and.bubble.right"
        case .today: return "sun.max"
        case .connections: return "cable.connector"
        case .workspace: return "folder"
        case .activity: return "waveform.path.ecg"
        case .settings: return "gearshape"
        }
    }

    /// Web route used while a screen is still hosted by the shared React surface.
    var webPath: String? {
        switch self {
        case .home: return nil
        case .chat: return "/conversation"
        case .today: return "/today"
        case .connections: return nil
        case .workspace: return "/workspace"
        case .activity: return "/activity"
        case .settings: return "/settings"
        }
    }
}

/// Primary macOS product shell.
///
/// Full product capacity is the goal: native destinations first, shared WebUI
/// surfaces for routes still migrating. Remote devices use WebUI alone against
/// the same controller (LAN / Tailscale).
struct ARESProductShell: View {
    @ObservedObject private var serverManager = WebUIServerManager.shared
    @ObservedObject private var config = ARESConfiguration.shared
    @State private var selection: ARESDestination? = .home
    @State private var readiness: ARESControllerClient.Readiness?
    @State private var connections: [ARESControllerClient.ConnectionRecord] = []
    @State private var lastError: String?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("ARES") {
                    ForEach([ARESDestination.home, .chat, .today, .connections, .workspace, .activity]) { dest in
                        Label(dest.title, systemImage: dest.systemImage)
                            .tag(dest)
                    }
                }
                Section("System") {
                    Label(ARESDestination.settings.title, systemImage: ARESDestination.settings.systemImage)
                        .tag(ARESDestination.settings)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .listStyle(.sidebar)
            .safeAreaInset(edge: .bottom) {
                serverStatusBar
            }
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: serverManager.serverHealth) {
            await refreshControllerState()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection ?? .home {
        case .home:
            ARESHomeView(
                serverHealth: serverManager.serverHealth,
                isRunning: serverManager.isRunning,
                readiness: readiness,
                connections: connections,
                lastError: lastError,
                onRefresh: { await refreshControllerState() },
                onOpenChat: { selection = .chat },
                onOpenConnections: { selection = .connections }
            )
        case .connections:
            ARESConnectionsNativeView(
                connections: connections,
                lastError: lastError,
                onRefresh: { await refreshControllerState() },
                onOpenWeb: { selection = .chat }
            )
        case .chat, .today, .workspace, .activity, .settings:
            if let path = (selection ?? .chat).webPath {
                ARESRoutedWebSurface(path: path)
            } else {
                Text("Unavailable")
            }
        }
    }

    private var serverStatusBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(serverManager.isRunning ? Color.green.opacity(0.85) : Color.orange.opacity(0.7))
                    .frame(width: 8, height: 8)
                Text(serverManager.serverHealth)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text("Controller · \(config.webuiHost):\(config.webuiPort)")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    @MainActor
    private func refreshControllerState() async {
        guard serverManager.isRunning else {
            readiness = nil
            connections = []
            return
        }
        let client = ARESControllerClient.sharedForConfiguration()
        do {
            async let ready = client.fetchReadiness()
            async let conns = client.fetchConnections()
            readiness = try await ready
            connections = try await conns
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}

// MARK: - Home (native)

struct ARESHomeView: View {
    let serverHealth: String
    let isRunning: Bool
    let readiness: ARESControllerClient.Readiness?
    let connections: [ARESControllerClient.ConnectionRecord]
    let lastError: String?
    let onRefresh: () async -> Void
    let onOpenChat: () -> Void
    let onOpenConnections: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("ARES")
                        .font(.largeTitle.weight(.semibold))
                    Text("ARES is the app. Your Companion is everything that is not a worker. Mac is primary; WebUI is remote.")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    statusCard(
                        title: "Profile",
                        value: readiness?.profileReady == true ? "Ready" : "Not ready",
                        ok: readiness?.profileReady == true
                    )
                    statusCard(
                        title: "Connection",
                        value: readiness?.connectionReady == true ? "Ready" : "None",
                        ok: readiness?.connectionReady == true
                    )
                    statusCard(
                        title: "Execution",
                        value: readiness?.executionAvailable == true ? "Available" : "Unavailable",
                        ok: readiness?.executionAvailable == true
                    )
                }

                GroupBox("Controller") {
                    VStack(alignment: .leading, spacing: 8) {
                        labeled("Server", serverHealth)
                        labeled("Running", isRunning ? "Yes" : "No")
                        if let lastError {
                            Text(lastError)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                GroupBox("Workers (explicit choice — no silent default)") {
                    let runtimes = connections.filter { $0.kind == "runtime" || $0.kind.contains("runtime") }
                    if runtimes.isEmpty {
                        Text("No workers reported. Open Connections to attach Ollama, jros, Hermes, or cloud.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(runtimes) { runtime in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(runtime.name).font(.headline)
                                    Text(runtime.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(runtime.selected ? "Selected" : runtime.state)
                                    .font(.caption)
                                    .foregroundStyle(runtime.available ? .green : .secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                HStack {
                    Button("Open Chat", action: onOpenChat)
                        .buttonStyle(.borderedProminent)
                    Button("Connections", action: onOpenConnections)
                    Button("Refresh") {
                        Task { await onRefresh() }
                    }
                }
            }
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func statusCard(title: String, value: String, ok: Bool) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(ok ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func labeled(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.callout)
    }
}

// MARK: - Connections (native)

struct ARESConnectionsNativeView: View {
    let connections: [ARESControllerClient.ConnectionRecord]
    let lastError: String?
    let onRefresh: () async -> Void
    let onOpenWeb: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Connections")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Refresh") {
                    Task { await onRefresh() }
                }
            }
            .padding()

            if let lastError {
                Text(lastError)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
            }

            List(connections) { connection in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(connection.name).font(.headline)
                        if connection.selected {
                            Text("Selected")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.2))
                                .clipShape(Capsule())
                        }
                        Spacer()
                        Text(connection.state)
                            .font(.caption)
                            .foregroundStyle(connection.available ? .green : .secondary)
                    }
                    Text(connection.kind)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !connection.detail.isEmpty {
                        Text(connection.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            Text("Your Companion owns conversations and context. Workers execute; they do not own your history.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding()
        }
    }
}

// MARK: - Routed web surface (migration host)

/// Hosts a WebUI route inside the native shell until that surface is fully native.
/// Remote clients hit the same routes without this shell.
struct ARESRoutedWebSurface: View {
    let path: String
    @ObservedObject private var serverManager = WebUIServerManager.shared
    @ObservedObject private var config = ARESConfiguration.shared

    var body: some View {
        if serverManager.isRunning,
           let url = URL(string: "http://\(config.webuiHost):\(config.webuiPort)\(path)") {
            WebViewRepresentable(url: url, serverManager: serverManager)
        } else {
            ContentUnavailableView(
                "Controller not ready",
                systemImage: "network.slash",
                description: Text(serverManager.serverHealth)
            )
        }
    }
}
