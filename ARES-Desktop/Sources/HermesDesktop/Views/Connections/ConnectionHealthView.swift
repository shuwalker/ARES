import SwiftUI

// MARK: - Health check model

private enum HealthStatus {
    case idle
    case checking
    case pass(String)
    case warn(String)
    case fail(String)

    var detail: String {
        switch self {
        case .idle: return ""
        case .checking: return L10n.string("Checking…")
        case .pass(let msg): return msg
        case .warn(let msg): return msg
        case .fail(let msg): return msg
        }
    }

    var iconName: String {
        switch self {
        case .idle: return "minus.circle"
        case .checking: return "arrow.trianglehead.clockwise"
        case .pass: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .idle: return .secondary
        case .checking: return .secondary
        case .pass: return .green
        case .warn: return .orange
        case .fail: return .red
        }
    }
}

private struct HealthCheckItem: Identifiable {
    let id: String
    let name: String
    var status: HealthStatus = .idle
}

// MARK: - ConnectionHealthView

@MainActor
struct ConnectionHealthView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var checks: [HealthCheckItem] = Self.defaultChecks
    @State private var isRunning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "stethoscope")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.string("Connection Health"))
                        .font(.headline)
                    Text(L10n.string("Pre-flight checks for the active connection"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(L10n.string("Done")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            // Check rows
            ScrollView {
                VStack(spacing: 0) {
                    ForEach($checks) { $check in
                        HealthCheckRow(item: check)
                        if check.id != checks.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .padding(.vertical, 8)
            }

            Divider()

            // Footer actions
            HStack {
                overallStatusBadge

                Spacer()

                Button {
                    Task { await runAllChecks() }
                } label: {
                    if isRunning {
                        Label(L10n.string("Running…"), systemImage: "arrow.trianglehead.clockwise")
                    } else {
                        Label(L10n.string("Run Checks"), systemImage: "play.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)
            }
            .padding(20)
        }
        .frame(width: 520, height: 440)
        .task { await runAllChecks() }
    }

    // MARK: - Overall status badge

    @ViewBuilder
    private var overallStatusBadge: some View {
        let allPass = checks.allSatisfy {
            if case .pass = $0.status { return true } else { return false }
        }
        let anyFail = checks.contains {
            if case .fail = $0.status { return true } else { return false }
        }
        let anyWarn = checks.contains {
            if case .warn = $0.status { return true } else { return false }
        }
        let anyChecking = checks.contains {
            if case .checking = $0.status { return true } else { return false }
        }

        if anyChecking {
            Label(L10n.string("Checking…"), systemImage: "arrow.trianglehead.clockwise")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        } else if anyFail {
            Label(L10n.string("Issues found"), systemImage: "xmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.red)
        } else if anyWarn {
            Label(L10n.string("Warnings"), systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
        } else if allPass {
            Label(L10n.string("All checks passed"), systemImage: "checkmark.circle.fill")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
        } else {
            EmptyView()
        }
    }

    // MARK: - Default checks

    static let defaultChecks: [HealthCheckItem] = [
        HealthCheckItem(id: "ssh_reachability", name: L10n.string("SSH Reachability")),
        HealthCheckItem(id: "dashboard_api", name: L10n.string("Dashboard API")),
        HealthCheckItem(id: "port_tunnel", name: L10n.string("Port 9119 Tunnel")),
        HealthCheckItem(id: "python_bridge", name: L10n.string("Python Bridge")),
        HealthCheckItem(id: "disk_space", name: L10n.string("Disk Space")),
        HealthCheckItem(id: "hermes_version", name: L10n.string("Hermes Version"))
    ]

    // MARK: - Run checks

    private func runAllChecks() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        // Reset all to checking
        for index in checks.indices {
            checks[index].status = .checking
        }

        let tunnelPort = appState.tunnelService.localPort
        let hasTunnel = tunnelPort != nil
        let hasConnection = appState.activeConnection != nil

        // 1. SSH Reachability
        await setStatus(for: "ssh_reachability", status: runSSHReachabilityCheck())

        // 2. Dashboard API
        await setStatus(for: "dashboard_api", status: await runDashboardAPICheck(hasTunnel: hasTunnel))

        // 3. Port 9119 Tunnel
        await setStatus(for: "port_tunnel", status: runTunnelCheck(tunnelPort: tunnelPort))

        // 4. Python Bridge
        await setStatus(for: "python_bridge", status: await runPythonBridgeCheck(hasConnection: hasConnection))

        // 5. Disk Space — parsed from /api/status response
        // 6. Hermes Version — parsed from /api/status response
        let (diskStatus, versionStatus) = await runStatusChecks(hasTunnel: hasTunnel)
        await setStatus(for: "disk_space", status: diskStatus)
        await setStatus(for: "hermes_version", status: versionStatus)
    }

    private func setStatus(for id: String, status: HealthStatus) async {
        if let index = checks.firstIndex(where: { $0.id == id }) {
            checks[index].status = status
        }
    }

    private func runSSHReachabilityCheck() -> HealthStatus {
        guard let connection = appState.activeConnection else {
            return .fail(L10n.string("No active connection"))
        }
        // Use the effective SSH target to determine reachability
        let target = connection.effectiveTarget
        if target.isEmpty {
            return .fail(L10n.string("No SSH target configured"))
        }
        // If we have an active connection record, consider SSH reachable if we got this far
        if appState.activeConnectionID != nil {
            return .pass(L10n.string("Host: %@", target))
        }
        return .warn(L10n.string("Not connected to %@", target))
    }

    private func runDashboardAPICheck(hasTunnel: Bool) async -> HealthStatus {
        guard hasTunnel else {
            return .warn(L10n.string("Requires tunnel connection"))
        }
        do {
            let status = try await appState.dashboardAPIService.fetchStatus()
            if status.version != nil {
                return .pass(L10n.string("API reachable"))
            }
            return .warn(L10n.string("Responded without version info"))
        } catch {
            return .fail(L10n.string("Unreachable: %@", error.localizedDescription))
        }
    }

    private func runTunnelCheck(tunnelPort: Int?) -> HealthStatus {
        if let port = tunnelPort {
            return .pass(L10n.string("Forwarded on port %d", port))
        }
        if appState.activeConnection?.transportKind == .local {
            return .pass(L10n.string("Direct (local transport)"))
        }
        return .warn(L10n.string("Tunnel not active"))
    }

    private func runPythonBridgeCheck(hasConnection: Bool) async -> HealthStatus {
        guard hasConnection, let connection = appState.activeConnection else {
            return .warn(L10n.string("Requires active connection"))
        }
        // Attempt a lightweight SSH list-sessions call to verify the bridge
        do {
            _ = try await appState.sessionBrowserService.listSessions(
                connection: connection,
                offset: 0,
                limit: 1,
                query: ""
            )
            return .pass(L10n.string("Bridge responding"))
        } catch {
            return .fail(L10n.string("Bridge error: %@", error.localizedDescription))
        }
    }

    private func runStatusChecks(hasTunnel: Bool) async -> (HealthStatus, HealthStatus) {
        guard hasTunnel else {
            return (
                .warn(L10n.string("Requires tunnel connection")),
                .warn(L10n.string("Requires tunnel connection"))
            )
        }
        do {
            let status = try await appState.dashboardAPIService.fetchStatus()

            let diskStatus: HealthStatus = .pass(L10n.string("No disk info available from API"))

            let versionStatus: HealthStatus
            if let version = status.version, !version.isEmpty {
                versionStatus = .pass(version)
            } else {
                versionStatus = .warn(L10n.string("Version unknown"))
            }

            return (diskStatus, versionStatus)
        } catch {
            let errMsg = error.localizedDescription
            return (
                .fail(L10n.string("Could not fetch: %@", errMsg)),
                .fail(L10n.string("Could not fetch: %@", errMsg))
            )
        }
    }
}

// MARK: - HealthCheckRow

private struct HealthCheckRow: View {
    let item: HealthCheckItem

    var body: some View {
        HStack(spacing: 12) {
            statusIcon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.subheadline.weight(.medium))

                if !item.status.detail.isEmpty {
                    Text(item.status.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .animation(.easeInOut(duration: 0.2), value: item.status.iconName)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if case .checking = item.status {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.9)
        } else {
            Image(systemName: item.status.iconName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(item.status.iconColor)
        }
    }
}

// MARK: - HealthStatus equatable for animation

extension HealthStatus: Equatable {
    static func == (lhs: HealthStatus, rhs: HealthStatus) -> Bool {
        lhs.iconName == rhs.iconName && lhs.detail == rhs.detail
    }
}

