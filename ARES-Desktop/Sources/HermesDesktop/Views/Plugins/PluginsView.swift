import SwiftUI

struct PluginsView: View {
    @EnvironmentObject private var appState: AppState

    // MARK: - Hub Data
    @State private var hubResponse: PluginsHubResponse?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isRescanning = false

    // MARK: - Install State
    @State private var installIdentifier = ""
    @State private var installForce = false
    @State private var installEnable = true
    @State private var isInstalling = false
    @State private var installResult: AgentPluginInstallResponse?
    @State private var installError: String?

    // MARK: - Action State
    @State private var operatingPluginName: String?
    @State private var actionError: String?

    // MARK: - Providers State
    @State private var selectedMemoryProvider = ""
    @State private var selectedContextEngine = ""
    @State private var isSavingProviders = false
    @State private var providersSaveError: String?
    @State private var providersSaveSuccess = false

    var body: some View {
        HermesPageContainer(width: .dashboard) {
            VStack(alignment: .leading, spacing: 24) {
                header
                content
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task(id: appState.activeConnectionID) {
            await loadPlugins()
        }
        .alert(item: $installResult) { result in
            Alert(
                title: Text(result.ok ? L10n.string("Plugin Installed") : L10n.string("Install Failed")),
                message: Text(installAlertMessage(for: result)),
                dismissButton: .default(Text(L10n.string("OK")))
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HermesPageHeader(
            title: "Plugins",
            subtitle: "Install, configure and manage agent plugins."
        ) {
            HStack(spacing: 10) {
                HermesRefreshButton(isRefreshing: isLoading) {
                    Task { await loadPlugins() }
                }

                Button {
                    Task { await rescanPlugins() }
                } label: {
                    if isRescanning {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(L10n.string("Rescanning…"))
                        }
                    } else {
                        Label(L10n.string("Rescan"), systemImage: "arrow.clockwise.circle")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isRescanning || isLoading)
                .help(L10n.string("Rescan plugins"))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && hubResponse == nil {
            HermesSurfacePanel {
                HermesLoadingState(label: "Loading plugins…", minHeight: 300)
            }
        } else if let error = errorMessage {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("Unable to load plugins"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else if let hub = hubResponse {
            pluginsLoadedView(hub: hub)
        } else {
            HermesSurfacePanel {
                HermesLoadingState(label: "Loading plugins…", minHeight: 300)
            }
        }
    }

    @ViewBuilder
    private func pluginsLoadedView(hub: PluginsHubResponse) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            providersPanel(hub: hub)
            installPanel
            pluginListPanel(hub: hub)
            orphanPluginsPanel(hub: hub)
        }
    }

    // MARK: - Providers Panel

    private func providersPanel(hub: PluginsHubResponse) -> some View {
        HermesSurfacePanel(
            title: "Providers",
            subtitle: "Configure global memory and context engine providers."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    providerPicker(
                        label: "Memory Provider",
                        selection: $selectedMemoryProvider,
                        options: hub.providers?.memoryOptions ?? []
                    )

                    providerPicker(
                        label: "Context Engine",
                        selection: $selectedContextEngine,
                        options: hub.providers?.contextOptions ?? []
                    )
                }

                if providersSaveSuccess {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Text(L10n.string("Providers saved successfully."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = providersSaveError {
                    HermesValidationMessage(text: error)
                }

                Button {
                    Task { await saveProviders() }
                } label: {
                    if isSavingProviders {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text(L10n.string("Saving…"))
                        }
                    } else {
                        Label(L10n.string("Save Providers"), systemImage: "opticaldisc")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(isSavingProviders)
            }
        }
    }

    private func providerPicker(label: String, selection: Binding<String>, options: [ProviderOption]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(label))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Picker(L10n.string(label), selection: selection) {
                Text(L10n.string("Select…"))
                    .tag("")

                ForEach(options) { option in
                    Text(option.name)
                        .tag(option.name)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 260)
        }
    }

    // MARK: - Install Panel

    private var installPanel: some View {
        HermesSurfacePanel(
            title: "Install Plugin",
            subtitle: "Install a new plugin by its identifier (package name or git URL)."
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    TextField(L10n.string("Plugin identifier…"), text: $installIdentifier)
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 280)

                    Toggle(L10n.string("Force"), isOn: $installForce)
                        .toggleStyle(.checkbox)

                    Toggle(L10n.string("Enable after install"), isOn: $installEnable)
                        .toggleStyle(.checkbox)

                    Button {
                        Task { await installPlugin() }
                    } label: {
                        if isInstalling {
                            HStack(spacing: 8) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(L10n.string("Installing…"))
                            }
                        } else {
                            Label(L10n.string("Install"), systemImage: "square.and.arrow.down")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(installIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isInstalling)
                }

                if let error = installError {
                    HermesValidationMessage(text: error)
                }

                if let actionError = actionError {
                    HermesValidationMessage(text: actionError)
                }
            }
        }
    }

    // MARK: - Plugin List Panel

    private func pluginListPanel(hub: PluginsHubResponse) -> some View {
        HermesSurfacePanel(
            title: "Installed Plugins",
            subtitle: hub.plugins.isEmpty ? "No plugins are currently installed." : "\(hub.plugins.count) plugin(s) discovered."
        ) {
            if hub.plugins.isEmpty {
                ContentUnavailableView(
                    L10n.string("No plugins installed"),
                    systemImage: "puzzlepiece.extension",
                    description: Text(L10n.string("Install a plugin using the form above, or run a rescan to discover existing plugins."))
                )
                .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(hub.plugins) { plugin in
                        PluginRowCard(
                            plugin: plugin,
                            isOperating: operatingPluginName == plugin.name
                        ) { action in
                            Task { await performPluginAction(action, plugin: plugin) }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Orphan Plugins Panel

    @ViewBuilder
    private func orphanPluginsPanel(hub: PluginsHubResponse) -> some View {
        if let orphans = hub.orphanDashboardPlugins, !orphans.isEmpty {
            HermesSurfacePanel(
                title: "Orphan Dashboard Plugins",
                subtitle: "These plugins have dashboard manifests but no corresponding agent plugin entry."
            ) {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(orphans) { orphan in
                        OrphanPluginRow(manifest: orphan)
                    }
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadPlugins() async {
        guard appState.activeConnection != nil, appState.dashboardAPIAvailable else {
            errorMessage = L10n.string("Plugin management requires an active connection.")
            return
        }

        isLoading = true
        errorMessage = nil
        actionError = nil
        installError = nil
        providersSaveError = nil
        providersSaveSuccess = false

        do {
            let response = try await appState.dashboardAPIService.getPluginsHub()
            hubResponse = response
            selectedMemoryProvider = response.providers?.memoryProvider ?? ""
            selectedContextEngine = response.providers?.contextEngine ?? ""
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func rescanPlugins() async {
        guard appState.dashboardAPIAvailable else { return }
        isRescanning = true
        actionError = nil

        do {
            let result = try await appState.dashboardAPIService.rescanPlugins()
            if result.ok {
                appState.setStatusMessage(L10n.string("Rescanned %@ plugins", "\(result.count ?? 0)"))
            } else {
                actionError = L10n.string("Rescan failed")
            }
            await loadPlugins()
        } catch {
            actionError = error.localizedDescription
        }

        isRescanning = false
    }

    private func installPlugin() async {
        guard appState.dashboardAPIAvailable else { return }
        let identifier = installIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !identifier.isEmpty else { return }

        isInstalling = true
        installError = nil
        installResult = nil

        do {
            let result = try await appState.dashboardAPIService.installAgentPlugin(
                identifier: identifier,
                force: installForce,
                enable: installEnable
            )
            installResult = result
            if result.ok {
                installIdentifier = ""
                installForce = false
                installEnable = true
                await loadPlugins()
            } else {
                installError = result.error ?? L10n.string("Installation failed")
            }
        } catch {
            installError = error.localizedDescription
        }

        isInstalling = false
    }

    private func saveProviders() async {
        guard appState.dashboardAPIAvailable else { return }
        isSavingProviders = true
        providersSaveError = nil
        providersSaveSuccess = false

        do {
            _ = try await appState.dashboardAPIService.savePluginProviders(
                memoryProvider: selectedMemoryProvider,
                contextEngine: selectedContextEngine
            )
            providersSaveSuccess = true
            await loadPlugins()
        } catch {
            providersSaveError = error.localizedDescription
        }

        isSavingProviders = false
    }

    // MARK: - Plugin Actions

    private func performPluginAction(_ action: PluginRowAction, plugin: HubAgentPluginRow) async {
        guard appState.dashboardAPIAvailable else { return }
        operatingPluginName = plugin.name
        actionError = nil

        do {
            switch action {
            case .enable:
                _ = try await appState.dashboardAPIService.enableAgentPlugin(name: plugin.name)
                appState.setStatusMessage(L10n.string("Enabled %@", plugin.name))
            case .disable:
                _ = try await appState.dashboardAPIService.disableAgentPlugin(name: plugin.name)
                appState.setStatusMessage(L10n.string("Disabled %@", plugin.name))
            case .update:
                let result = try await appState.dashboardAPIService.updateAgentPlugin(name: plugin.name)
                if result.ok {
                    appState.setStatusMessage(
                        result.unchanged == true
                            ? L10n.string("%@ is up to date", plugin.name)
                            : L10n.string("Updated %@", plugin.name)
                    )
                } else {
                    actionError = result.error ?? L10n.string("Update failed for %@", plugin.name)
                }
            case .remove:
                _ = try await appState.dashboardAPIService.removeAgentPlugin(name: plugin.name)
                appState.setStatusMessage(L10n.string("Removed %@", plugin.name))
            }
            await loadPlugins()
        } catch {
            actionError = error.localizedDescription
        }

        operatingPluginName = nil
    }

    // MARK: - Helpers

    private func installAlertMessage(for result: AgentPluginInstallResponse) -> String {
        var parts: [String] = []
        if let pluginName = result.pluginName {
            parts.append(L10n.string("Plugin: %@", pluginName))
        }
        if let warnings = result.warnings, !warnings.isEmpty {
            parts.append(L10n.string("Warnings: %@", warnings.joined(separator: ", ")))
        }
        if let missing = result.missingEnv, !missing.isEmpty {
            parts.append(L10n.string("Missing environment variables: %@", missing.joined(separator: ", ")))
        }
        if let path = result.afterInstallPath {
            parts.append(L10n.string("Installed at: %@", path))
        }
        if let error = result.error {
            parts.append(L10n.string("Error: %@", error))
        }
        if parts.isEmpty {
            return result.ok ? L10n.string("Installation completed.") : L10n.string("Installation failed.")
        }
        return parts.joined(separator: "\n")
    }
}

// MARK: - Plugin Row Card

enum PluginRowAction {
    case enable
    case disable
    case update
    case remove
}

private struct PluginRowCard: View {
    let plugin: HubAgentPluginRow
    let isOperating: Bool
    let onAction: (PluginRowAction) -> Void

    private var statusTint: Color {
        switch plugin.runtimeStatus {
        case .enabled:
            return Color.green
        case .disabled:
            return Color.orange
        case .inactive:
            return Color.gray
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(plugin.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        HermesBadge(
                            text: plugin.runtimeStatus.rawValue.capitalized,
                            tint: statusTint,
                            systemImage: "circle.fill"
                        )

                        if plugin.authRequired == true {
                            HermesBadge(
                                text: "Auth Required",
                                tint: .red,
                                systemImage: "lock.fill"
                            )
                        }
                    }

                    HStack(spacing: 8) {
                        if let version = plugin.version, !version.isEmpty {
                            Text("v\(version)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let source = plugin.source, !source.isEmpty {
                            Text(source)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: 12)

                actionButtons
            }

            if let description = plugin.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            if let path = plugin.path, !path.isEmpty {
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .fill(HermesTheme.rowFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
        }
        .opacity(isOperating ? 0.6 : 1)
    }

    private var actionButtons: some View {
        HStack(spacing: 8) {
            switch plugin.runtimeStatus {
            case .disabled:
                Button {
                    onAction(.enable)
                } label: {
                    Label(L10n.string("Enable"), systemImage: "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isOperating)
            case .enabled, .inactive:
                Button {
                    onAction(.disable)
                } label: {
                    Label(L10n.string("Disable"), systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isOperating)
            }

            if plugin.canUpdateGit == true {
                Button {
                    onAction(.update)
                } label: {
                    if isOperating {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label(L10n.string("Update"), systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isOperating)
            }

            if plugin.canRemove == true {
                Button {
                    onAction(.remove)
                } label: {
                    Label(L10n.string("Remove"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.red)
                .disabled(isOperating)
            }
        }
    }
}

// MARK: - Orphan Plugin Row

private struct OrphanPluginRow: View {
    let manifest: PluginManifest

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(manifest.name)
                    .font(.subheadline.weight(.semibold))

                if let version = manifest.version, !version.isEmpty {
                    HermesBadge(text: "v\(version)", tint: .secondary)
                }

                if let source = manifest.source, !source.isEmpty {
                    HermesBadge(text: source, tint: .secondary)
                }
            }

            if let description = manifest.description, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HermesTheme.insetCornerRadius, style: .continuous)
                .fill(HermesTheme.insetFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.insetCornerRadius, style: .continuous)
                .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
        }
    }
}

// MARK: - Alert Item

extension AgentPluginInstallResponse: Identifiable {
    public var id: String {
        "\(ok)-\(pluginName ?? "unknown")-\(UUID().uuidString)"
    }
}
