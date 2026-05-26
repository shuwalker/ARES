import SwiftUI

struct ConnectionsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var editingConnection = ConnectionProfile()
    @State private var editorPresentationID = UUID()
    @State private var isPresentingEditor = false
    @State private var editingExistingConnection = false

    var body: some View {
        HermesPageContainer(width: .standard) {
            VStack(alignment: .leading, spacing: 24) {
                HermesPageHeader(
                    title: "Hosts",
                    subtitle: "Alias-first SSH profiles for every Hermes workspace, from a Raspberry Pi to another Mac or a remote VPS."
                ) {
                    Button {
                        presentEditor(for: ConnectionProfile(), isEditing: false)
                    } label: {
                        Label(L10n.string("Add Host"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                if appState.connectionStore.connections.isEmpty {
                    HermesSurfacePanel {
                        VStack(alignment: .leading, spacing: 18) {
                            ContentUnavailableView(
                                L10n.string("No hosts yet"),
                                systemImage: "network.slash",
                                description: Text(L10n.string("Create your first SSH profile to connect Hermes Desktop to a Raspberry Pi, another Mac, a VPS, or this Mac via localhost."))
                            )

                            Button {
                                presentEditor(for: ConnectionProfile(), isEditing: false)
                            } label: {
                                Label(L10n.string("Add First Host"), systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .frame(maxWidth: .infinity, minHeight: 280)
                    }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            hostsPanel
                                .frame(minWidth: 640, maxWidth: .infinity)

                            connectionGuidePanel
                                .frame(width: 320)
                        }

                        VStack(alignment: .leading, spacing: 16) {
                            hostsPanel
                            connectionGuidePanel
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $isPresentingEditor) {
            ConnectionEditorSheet(
                connection: editingConnection,
                isEditing: editingExistingConnection
            ) { updatedConnection in
                appState.saveConnection(updatedConnection)
            }
            .id(editorPresentationID)
        }
        .onAppear {
            presentPendingNewConnectionEditorIfNeeded()
        }
        .onChange(of: appState.pendingNewConnectionEditorRequestID) { _, _ in
            presentPendingNewConnectionEditorIfNeeded()
        }
    }

    private var hostsPanel: some View {
        HermesSurfacePanel(
            title: "Saved Hosts",
            subtitle: "Choose the active host for discovery, files, sessions and terminal access."
        ) {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(appState.connectionStore.connections) { connection in
                    ConnectionCard(
                        connection: connection,
                        isActive: appState.activeConnectionID == connection.id,
                        onConnect: { appState.connect(to: connection) },
                        onTest: { appState.testConnection(connection) },
                        onEdit: {
                            presentEditor(for: connection, isEditing: true)
                        },
                        onDelete: { appState.deleteConnection(connection) }
                    )
                }
            }
        }
    }

    private var connectionGuidePanel: some View {
        HermesSurfacePanel(
            title: "Connection Guide",
            subtitle: "Keep the setup technical, but easy to scan and reason about."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HermesInsetSurface {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.string("Recommended"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(L10n.string("Use an SSH alias whenever possible. It keeps the system SSH config as the source of truth and makes profiles easier to move between machines."))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HermesInsetSurface {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.string("Authentication"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Text(L10n.string("Profiles work best when SSH already works from this Mac without prompts. Password login may still exist on the host, but the app expects a non-interactive SSH path such as keys or ssh-agent."))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(L10n.string("The Mac and Hermes host do not need to share the same Wi-Fi. What matters is that normal ssh from this Mac can reach the host over LAN, public IP, VPN, or Tailscale."))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    GuideRow(label: "Alias", value: "hermes-home")
                    GuideRow(label: "Hostname", value: "mac-studio.local")
                    GuideRow(label: "LAN or public IP", value: "192.168.1.24 or 203.0.113.10")
                    GuideRow(label: "Same Mac", value: "localhost or a local SSH alias")
                }
            }
        }
    }

    private func presentEditor(for connection: ConnectionProfile, isEditing: Bool) {
        editingConnection = connection
        editingExistingConnection = isEditing
        editorPresentationID = UUID()
        isPresentingEditor = true
    }

    private func presentPendingNewConnectionEditorIfNeeded() {
        guard let requestID = appState.pendingNewConnectionEditorRequestID else { return }
        presentEditor(for: ConnectionProfile(), isEditing: false)
        appState.consumeNewConnectionEditorRequest(requestID)
    }
}

private struct GuideRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(L10n.string(label))
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

private struct ConnectionCard: View {
    let connection: ConnectionProfile
    let isActive: Bool
    let onConnect: () -> Void
    let onTest: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(connection.label)
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(connection.displayDestination)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    Spacer(minLength: 12)

                    VStack(alignment: .trailing, spacing: 8) {
                        if isActive {
                            HermesBadge(text: "Active", tint: .accentColor)
                        }

                        HermesBadge(
                            text: connection.trimmedAlias != nil ? "Alias" : "Direct host",
                            tint: .secondary
                        )
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        metadataRow(label: "Target", value: resolvedTarget)
                        metadataRow(label: "SSH user", value: connection.trimmedUser ?? "Default")
                        metadataRow(label: "Port", value: displayPort)
                        metadataRow(label: hermesScopeLabel, value: hermesScopeValue)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        metadataRow(label: "Target", value: resolvedTarget)
                        metadataRow(label: "SSH user", value: connection.trimmedUser ?? "Default")
                        metadataRow(label: "Port", value: displayPort)
                        metadataRow(label: hermesScopeLabel, value: hermesScopeValue)
                    }
                }

                if let lastConnectedAt = connection.lastConnectedAt {
                    Text(L10n.string("Last connected %@", DateFormatters.relativeFormatter().localizedString(for: lastConnectedAt, relativeTo: .now)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        primaryActions
                        Spacer(minLength: 12)
                        destructiveAction
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        primaryActions
                        destructiveAction
                    }
                }
            }
        }
    }

    private var primaryActions: some View {
        HStack(spacing: 10) {
            Button(L10n.string("Use Host"), action: onConnect)
                .buttonStyle(.borderedProminent)
                .disabled(isActive)

            Button(L10n.string("Test"), action: onTest)
                .buttonStyle(.bordered)

            Button(L10n.string("Edit"), action: onEdit)
                .buttonStyle(.bordered)
        }
    }

    private var destructiveAction: some View {
        Button(L10n.string("Remove"), role: .destructive, action: onDelete)
            .buttonStyle(.borderless)
    }

    private func metadataRow(label: String, value: String) -> some View {
        HermesLabeledValue(
            label: label,
            value: value,
            isMonospaced: label != "SSH user" || value != "Default"
        )
    }

    private var resolvedTarget: String {
        connection.trimmedAlias ?? connection.trimmedHost ?? "Not set"
    }

    private var hermesScopeLabel: String {
        connection.usesCustomHermesHome ? "Custom Hermes home" : "Hermes profile"
    }

    private var hermesScopeValue: String {
        connection.trimmedCustomHermesHomePath ?? connection.resolvedHermesProfileName
    }

    private var displayPort: String {
        if let port = connection.resolvedPort {
            return String(port)
        }
        return "Default"
    }
}
