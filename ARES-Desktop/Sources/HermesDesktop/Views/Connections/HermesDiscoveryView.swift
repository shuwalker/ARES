import SwiftUI

/// Onboarding sheet shown when scanning for nearby Hermes instances.
/// Can also be presented from ConnectionsView at any time.
@MainActor
struct HermesDiscoveryView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Called when the user wants to open the editor pre-filled with a profile
    let onOpenEditor: (ConnectionProfile) -> Void

    @StateObject private var discovery = HermesDiscoveryService()
    @State private var invitePasteError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HermesPageHeader(
                        title: "Find Hermes",
                        subtitle: "ARES scans for Hermes instances running on this Mac, your local network, and SSH hosts listed in your SSH config."
                    )

                    // Scanning status
                    if discovery.isScanning {
                        HStack(spacing: 10) {
                            ProgressView()
                                .controlSize(.small)
                            Text(L10n.string("Scanning…"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Error from invite paste
                    if let error = invitePasteError {
                        HermesInsetSurface {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    if discovery.discoveredHosts.isEmpty && !discovery.isScanning {
                        HermesSurfacePanel {
                            ContentUnavailableView(
                                L10n.string("Nothing found"),
                                systemImage: "magnifyingglass",
                                description: Text(L10n.string("No Hermes instances were found. Make sure Hermes is running or paste an invite code to connect manually."))
                            )
                            .frame(maxWidth: .infinity, minHeight: 180)
                        }
                    } else {
                        // localhost group
                        let localHosts = discovery.discoveredHosts.filter { $0.transport == .localhost }
                        if !localHosts.isEmpty {
                            hostGroup(
                                title: "On this Mac",
                                subtitle: "Hermes is running locally.",
                                hosts: localHosts
                            )
                        }

                        // LAN / direct HTTP group
                        let lanHosts = discovery.discoveredHosts.filter { $0.transport == .directHTTP }
                        if !lanHosts.isEmpty {
                            hostGroup(
                                title: "On your network",
                                subtitle: "Found via Bonjour / mDNS on your local network.",
                                hosts: lanHosts
                            )
                        }

                        // SSH suggestions group
                        let sshHosts = discovery.discoveredHosts.filter { $0.transport == .ssh }
                        if !sshHosts.isEmpty {
                            hostGroup(
                                title: "SSH hosts",
                                subtitle: "From your ~/.ssh/config — add credentials to connect.",
                                hosts: sshHosts
                            )
                        }
                    }

                    // Bottom actions
                    HermesSurfacePanel {
                        VStack(alignment: .leading, spacing: 12) {
                            Button {
                                pasteInviteCode()
                            } label: {
                                Label(L10n.string("Paste Invite Code"), systemImage: "doc.on.clipboard")
                            }
                            .buttonStyle(.bordered)

                            Button {
                                dismiss()
                                onOpenEditor(ConnectionProfile())
                            } label: {
                                Label(L10n.string("Set Up Manually"), systemImage: "gear")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .frame(maxWidth: 680, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Close")) {
                        discovery.stopScan()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await discovery.startScan() }
                    } label: {
                        Label(L10n.string("Scan Again"), systemImage: "arrow.clockwise")
                    }
                    .disabled(discovery.isScanning)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
        .task {
            await discovery.startScan()
        }
        .onDisappear {
            discovery.stopScan()
        }
    }

    // MARK: - Host group

    private func hostGroup(title: String, subtitle: String, hosts: [DiscoveredHermesHost]) -> some View {
        HermesSurfacePanel(title: title, subtitle: subtitle) {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(hosts) { host in
                    DiscoveredHostCard(host: host) {
                        connectToHost(host)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func connectToHost(_ host: DiscoveredHermesHost) {
        switch host.transport {
        case .localhost, .directHTTP:
            // Build a DirectHTTP profile and connect immediately
            let profile = ConnectionProfile(
                label: host.displayName,
                sshHost: host.hostname,
                transportMode: .directHTTP,
                dashboardPort: host.port != 9119 ? host.port : nil
            )
            appState.saveConnection(profile)
            appState.connect(to: profile)
            dismiss()

        case .ssh:
            // Pre-fill editor with hostname, user provides credentials
            let profile = ConnectionProfile(
                label: host.displayName,
                sshHost: host.hostname,
                transportMode: .sshTunnel
            )
            dismiss()
            onOpenEditor(profile)
        }
    }

    private func pasteInviteCode() {
        invitePasteError = nil

        guard let raw = NSPasteboard.general.string(forType: .string),
              raw.hasPrefix(ConnectionInviteService.scheme) else {
            invitePasteError = L10n.string("No invite code found on the clipboard. Copy an ares:// code first.")
            return
        }

        do {
            let profile = try ConnectionInviteService.parse(raw)
            dismiss()
            onOpenEditor(profile)
        } catch {
            invitePasteError = error.localizedDescription
        }
    }
}

// MARK: - Discovered host card

private struct DiscoveredHostCard: View {
    let host: DiscoveredHermesHost
    let onConnect: () -> Void

    var body: some View {
        HermesInsetSurface {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(host.displayName)
                        .font(.headline)

                    HStack(spacing: 8) {
                        Text(host.hostname)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)

                        if host.port != 9119 {
                            Text(":\(host.port)")
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        if let version = host.hermesVersion {
                            HermesBadge(text: version, tint: .accentColor)
                        }

                        transportBadge
                    }
                }

                Spacer(minLength: 10)

                Button(connectLabel, action: onConnect)
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var connectLabel: String {
        switch host.transport {
        case .localhost: return L10n.string("Connect Instantly")
        case .directHTTP: return L10n.string("Connect via HTTP")
        case .ssh: return L10n.string("Connect via SSH")
        }
    }

    private var transportBadge: some View {
        Group {
            switch host.transport {
            case .localhost:
                HermesBadge(text: "localhost", tint: .green)
            case .directHTTP:
                HermesBadge(text: "LAN", tint: .blue)
            case .ssh:
                HermesBadge(text: "SSH", tint: .secondary)
            }
        }
    }
}
