import SwiftUI

struct ConnectionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable {
        case label
        case alias
        case host
        case user
        case port
        case dashboardPort
        case hermesProfile
        case customHermesHome
    }

    @State private var draft: ConnectionProfile
    @State private var portText: String
    @State private var dashboardPortText: String
    @State private var showsCustomHermesHomeOptions: Bool
    @State private var inviteBannerVisible: Bool = false
    @State private var inviteBannerError: String? = nil
    @FocusState private var focusedField: Field?
    let isEditing: Bool
    let onSave: (ConnectionProfile) -> Void

    init(connection: ConnectionProfile, isEditing: Bool, onSave: @escaping (ConnectionProfile) -> Void) {
        _draft = State(initialValue: connection)
        _portText = State(initialValue: connection.sshPort.map(String.init) ?? "")
        _dashboardPortText = State(initialValue: connection.dashboardPort.map(String.init) ?? "")
        _showsCustomHermesHomeOptions = State(initialValue: connection.customHermesHomePath?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
        self.isEditing = isEditing
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HermesPageHeader(
                        title: isEditing ? "Edit Host" : "New Host",
                        subtitle: "Set the connection details ARES should use for discovery, file editing, sessions and terminal access."
                    )

                    // Invite code paste banner
                    if inviteBannerVisible {
                        HermesInsetSurface {
                            HStack(spacing: 10) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.accentColor)
                                Text(L10n.string("Connection details filled from invite code. Add your SSH credentials to connect."))
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.horizontal, 0)
                    }

                    if let error = inviteBannerError {
                        HermesInsetSurface {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.orange)
                                Text(error)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }

                    // Paste invite code button at the top
                    Button {
                        pasteInviteCode()
                    } label: {
                        Label(L10n.string("Paste Invite Code"), systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)

                    // Transport mode picker
                    HermesSurfacePanel(
                        title: "Transport",
                        subtitle: "Choose how ARES connects to this Hermes instance."
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            Picker(L10n.string("Transport Mode"), selection: $draft.transportMode) {
                                ForEach(TransportMode.allCases, id: \.self) { mode in
                                    Text(transportModeLabel(mode)).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)

                            switch draft.transportMode {
                            case .sshTunnel:
                                Text(L10n.string("ARES connects via SSH and forwards the dashboard port through an encrypted tunnel. Recommended for all connections."))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            case .directHTTP:
                                HermesInsetSurface {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(L10n.string("Direct HTTP (LAN)"))
                                            .font(.headline)
                                        Text(L10n.string("Use Direct HTTP only on trusted networks. SSH Tunnel is more secure. No SSH key or user is required, but Hermes must be reachable directly at the host and port below."))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }

                    HermesSurfacePanel(
                        title: "Connection Details",
                        subtitle: connectionDetailSubtitle
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            EditorField(label: "Name") {
                                TextField(L10n.string("Home Pi, Studio Mac, Prod VPS"), text: $draft.label)
                                    .focused($focusedField, equals: .label)
                                    .textFieldStyle(.roundedBorder)
                            }

                            if draft.transportMode == .sshTunnel {
                                EditorField(label: "SSH alias") {
                                    TextField(L10n.string("hermes-home"), text: $draft.sshAlias)
                                        .focused($focusedField, equals: .alias)
                                        .textFieldStyle(.roundedBorder)
                                }
                            }

                            EditorField(label: hostFieldLabel) {
                                TextField(L10n.string("mac-studio.local, 203.0.113.10, localhost"), text: $draft.sshHost)
                                    .focused($focusedField, equals: .host)
                                    .textFieldStyle(.roundedBorder)
                            }

                            if draft.transportMode == .directHTTP {
                                EditorField(label: "Dashboard port") {
                                    TextField("9119", text: $dashboardPortText)
                                        .focused($focusedField, equals: .dashboardPort)
                                        .textFieldStyle(.roundedBorder)
                                }
                            } else {
                                ViewThatFits(in: .horizontal) {
                                    HStack(alignment: .top, spacing: 14) {
                                        EditorField(label: "SSH user") {
                                            TextField("alex", text: $draft.sshUser)
                                                .focused($focusedField, equals: .user)
                                                .textFieldStyle(.roundedBorder)
                                        }

                                        EditorField(label: "SSH port") {
                                            TextField("22", text: $portText)
                                                .focused($focusedField, equals: .port)
                                                .textFieldStyle(.roundedBorder)
                                        }
                                    }

                                    VStack(alignment: .leading, spacing: 14) {
                                        EditorField(label: "SSH user") {
                                            TextField("alex", text: $draft.sshUser)
                                                .focused($focusedField, equals: .user)
                                                .textFieldStyle(.roundedBorder)
                                        }

                                        EditorField(label: "SSH port") {
                                            TextField("22", text: $portText)
                                                .focused($focusedField, equals: .port)
                                                .textFieldStyle(.roundedBorder)
                                        }
                                    }
                                }

                                EditorField(label: "Hermes profile") {
                                    TextField(L10n.string("default or researcher"), text: hermesProfileBinding)
                                        .focused($focusedField, equals: .hermesProfile)
                                        .textFieldStyle(.roundedBorder)
                                }

                                DisclosureGroup(
                                    isExpanded: $showsCustomHermesHomeOptions
                                ) {
                                    VStack(alignment: .leading, spacing: 10) {
                                        EditorField(label: "Remote Hermes home path") {
                                            TextField(L10n.string("~/.hermes-work or /opt/data"), text: customHermesHomeBinding)
                                                .focused($focusedField, equals: .customHermesHome)
                                                .textFieldStyle(.roundedBorder)
                                        }

                                        Text(L10n.string("Only use this if Hermes lives outside the standard `~/.hermes` or `~/.hermes/profiles/<name>` layout on the remote host."))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)

                                        Text(L10n.string("Leave this empty for the normal setup. When set, ARES uses this path as `HERMES_HOME` for Sessions, Files, Skills, Usage, Cron, chat, and Terminal."))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .padding(.top, 8)
                                } label: {
                                    Text(L10n.string("Custom Hermes home (advanced)"))
                                        .font(.headline)
                                }
                            }

                            if let validationMessage {
                                HermesValidationMessage(text: validationMessage)
                            }
                        }
                    }

                    HermesSurfacePanel(
                        title: "How Hermes Connects",
                        subtitle: "The goal is to keep the profile understandable without hiding the technical model."
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            if draft.transportMode == .sshTunnel {
                                ConnectionHintRow(
                                    title: "Preferred setup",
                                    detail: "Use an SSH alias when possible. It keeps the system SSH config as the source of truth."
                                )

                                ConnectionHintRow(
                                    title: "Same Mac",
                                    detail: "If Hermes runs on this Mac, stay with the SSH model and use localhost, the local hostname, or a local SSH alias."
                                )

                                ConnectionHintRow(
                                    title: "Authentication",
                                    detail: "SSH must already work from this Mac without interactive prompts. Password login may still exist on the host, but ARES expects keys, an SSH agent, or another non-interactive SSH path for the actual connection it uses."
                                )

                                ConnectionHintRow(
                                    title: "Network path",
                                    detail: "The Mac and Hermes host do not need to be on the same Wi-Fi. Local network, public IP, VPN, or Tailscale all work as long as standard ssh from this Mac reaches the host."
                                )

                                if draft.trimmedAlias != nil && draft.trimmedHost != nil {
                                    HermesInsetSurface {
                                        Text(L10n.string("The SSH alias currently takes priority over Host. The Host value is preserved in the profile, but it will be ignored while the alias is present."))
                                            .font(.subheadline)
                                            .foregroundStyle(.orange)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                } else {
                                    ConnectionHintRow(
                                        title: "Overrides",
                                        detail: "SSH user and port are optional. Leave them empty to keep the remote defaults."
                                    )
                                }

                                HermesInsetSurface {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(L10n.string("Hermes profile"))
                                            .font(.headline)

                                        Text(L10n.string("Leave it empty for the default Hermes home at `~/.hermes`. Set a profile name like `researcher` to target `~/.hermes/profiles/researcher` on the same host."))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            } else {
                                ConnectionHintRow(
                                    title: "Direct HTTP",
                                    detail: "ARES calls the Hermes dashboard API directly over HTTP. No SSH is used. The dashboard must be accessible on the network at the host and port you enter."
                                )
                                ConnectionHintRow(
                                    title: "Security",
                                    detail: "Use Direct HTTP only on trusted local networks. SSH Tunnel is strongly preferred for any connection that leaves your LAN."
                                )
                            }
                        }
                    }

                    if draft.transportMode == .sshTunnel {
                        HermesSurfacePanel(
                            title: "Examples",
                            subtitle: "A few common patterns that work well with ARES."
                        ) {
                            VStack(alignment: .leading, spacing: 12) {
                                ExampleValueRow(label: "Raspberry Pi", value: "Alias `hermes-home` or host `raspberrypi.local`")
                                ExampleValueRow(label: "Remote Mac", value: "Host `mac-studio.local`")
                                ExampleValueRow(label: "VPS", value: "Host `vps.example.com` or `203.0.113.10`")
                                ExampleValueRow(label: "Same Mac", value: "Host `localhost` or a local SSH alias")
                            }
                        }
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("Save")) {
                        var updatedDraft = draft
                        updatedDraft.sshPort = parsedPort
                        updatedDraft.dashboardPort = parsedDashboardPort
                        onSave(updatedDraft)
                        dismiss()
                    }
                    .disabled(!isDraftValid)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 560)
        .onAppear {
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                focusedField = .label
            }
        }
    }

    // MARK: - Dynamic labels

    private var connectionDetailSubtitle: String {
        switch draft.transportMode {
        case .sshTunnel:
            return L10n.string("Give the host a clear name, then prefer an SSH alias whenever you have one.")
        case .directHTTP:
            return L10n.string("Give the host a clear name and enter the host address and dashboard port.")
        }
    }

    private var hostFieldLabel: String {
        switch draft.transportMode {
        case .sshTunnel: return "Host or IP address"
        case .directHTTP: return "Host or IP address"
        }
    }

    private func transportModeLabel(_ mode: TransportMode) -> String {
        switch mode {
        case .sshTunnel: return L10n.string("SSH Tunnel")
        case .directHTTP: return L10n.string("Direct HTTP (LAN)")
        }
    }

    // MARK: - Invite code

    private func pasteInviteCode() {
        inviteBannerError = nil
        inviteBannerVisible = false

        guard let raw = NSPasteboard.general.string(forType: .string),
              raw.hasPrefix(ConnectionInviteService.scheme) else {
            inviteBannerError = L10n.string("No invite code found on the clipboard. Copy an ares:// code first.")
            return
        }

        do {
            let parsed = try ConnectionInviteService.parse(raw)
            // Preserve existing label if draft already has one and parsed doesn't
            let newLabel = parsed.label.isEmpty ? draft.label : parsed.label
            draft = parsed
            draft.label = newLabel
            dashboardPortText = parsed.dashboardPort.map(String.init) ?? ""
            portText = parsed.sshPort.map(String.init) ?? ""
            inviteBannerVisible = true
        } catch {
            inviteBannerError = error.localizedDescription
        }
    }

    // MARK: - Port parsing

    private var parsedPort: Int? {
        let trimmed = portText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed), (1...65_535).contains(value) else { return nil }
        return value
    }

    private var parsedDashboardPort: Int? {
        let trimmed = dashboardPortText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let value = Int(trimmed), (1...65_535).contains(value) else { return nil }
        return value
    }

    private var isDraftValid: Bool {
        validationMessage == nil
    }

    private var validationMessage: String? {
        let hasValidPort = portText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedPort != nil
        let hasValidDashboardPort = dashboardPortText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || parsedDashboardPort != nil

        var candidate = draft
        candidate.sshPort = parsedPort
        candidate.dashboardPort = parsedDashboardPort

        if candidate.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.string("Name is required.")
        }

        if candidate.transportMode == .sshTunnel && candidate.trimmedAlias == nil && candidate.trimmedHost == nil {
            return L10n.string("Add an SSH alias or host.")
        }

        if candidate.transportMode == .directHTTP && candidate.sshHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return L10n.string("Host or IP address is required for Direct HTTP.")
        }

        if !hasValidPort {
            return L10n.string("Enter a valid SSH port from 1 to 65535.")
        }

        if !hasValidDashboardPort {
            return L10n.string("Enter a valid dashboard port from 1 to 65535.")
        }

        return candidate.validationError
    }

    private var hermesProfileBinding: Binding<String> {
        Binding {
            draft.hermesProfile ?? ""
        } set: { newValue in
            draft.hermesProfile = newValue
        }
    }

    private var customHermesHomeBinding: Binding<String> {
        Binding {
            draft.customHermesHomePath ?? ""
        } set: { newValue in
            draft.customHermesHomePath = newValue
        }
    }
}

private struct EditorField<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(label))
                .font(.caption)
                .foregroundStyle(.secondary)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ConnectionHintRow: View {
    let title: String
    let detail: String

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.string(title))
                    .font(.headline)

                Text(L10n.string(detail))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct ExampleValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HermesInsetSurface {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.string(label))
                    .font(.headline)

                Text(value)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
