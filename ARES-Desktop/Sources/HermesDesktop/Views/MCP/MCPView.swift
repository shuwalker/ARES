import SwiftUI

// MARK: - MCPView

struct MCPView: View {
    @EnvironmentObject private var appState: AppState

    @State private var selectedTab: MCPTab = .installed
    @State private var marketplaceQuery = ""
    @State private var showAddServerSheet = false
    @State private var serverToDelete: MCPServer?
    @State private var isSearchingMarketplace = false

    enum MCPTab: String, CaseIterable, Identifiable {
        case installed = "Installed"
        case marketplace = "Marketplace"
        var id: String { rawValue }
    }

    var body: some View {
        HermesPageContainer(width: .dashboard) {
            VStack(alignment: .leading, spacing: 24) {
                header

                if !appState.dashboardAPIAvailable {
                    unavailableView
                } else {
                    tabContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task(id: appState.activeConnectionID) {
            guard appState.dashboardAPIAvailable else { return }
            await appState.loadMCPServers()
        }
        .sheet(isPresented: $showAddServerSheet) {
            AddMCPServerSheet { server in
                Task { await appState.addMCPServer(server) }
            }
        }
        .alert(L10n.string("Remove server?"), isPresented: .constant(serverToDelete != nil)) {
            Button(L10n.string("Remove"), role: .destructive) {
                if let server = serverToDelete {
                    Task { await appState.deleteMCPServer(id: server.id) }
                }
                serverToDelete = nil
            }
            Button(L10n.string("Cancel"), role: .cancel) {
                serverToDelete = nil
            }
        } message: {
            if let server = serverToDelete {
                Text(L10n.string("%@ will be removed from your MCP configuration.", server.name))
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HermesPageHeader(
            title: "MCP Servers",
            subtitle: "Manage Model Context Protocol servers for extended capabilities."
        ) {
            HStack(spacing: 10) {
                HermesRefreshButton(isRefreshing: appState.isLoadingMCP) {
                    Task { await appState.loadMCPServers() }
                }

                if selectedTab == .installed {
                    Button {
                        showAddServerSheet = true
                    } label: {
                        Label(L10n.string("Add Server"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(!appState.dashboardAPIAvailable)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: - Unavailable

    private var unavailableView: some View {
        HermesSurfacePanel {
            ContentUnavailableView(
                L10n.string("Dashboard API Unavailable"),
                systemImage: "server.rack",
                description: Text(L10n.string("MCP server management requires a local Hermes connection or an active SSH tunnel."))
            )
            .frame(maxWidth: .infinity, minHeight: 300)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        Picker(L10n.string("Tab"), selection: $selectedTab) {
            ForEach(MCPTab.allCases) { tab in
                Text(L10n.string(tab.rawValue)).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .frame(width: 260)

        switch selectedTab {
        case .installed:
            installedContent
        case .marketplace:
            marketplaceContent
        }
    }

    // MARK: - Installed Tab

    @ViewBuilder
    private var installedContent: some View {
        if appState.isLoadingMCP && appState.mcpServers.isEmpty {
            HermesSurfacePanel {
                HermesLoadingState(label: "Loading MCP servers…", minHeight: 300)
            }
        } else if let error = appState.mcpError, appState.mcpServers.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("Unable to load MCP servers"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else if appState.mcpServers.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("No MCP Servers"),
                    systemImage: "server.rack",
                    description: Text(L10n.string("Add a server using the \"Add Server\" button or browse the Marketplace tab."))
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else {
            serverListPanel
        }
    }

    private var serverListPanel: some View {
        HermesSurfacePanel(
            title: "Configured Servers",
            subtitle: "\(appState.mcpServers.count) server(s) configured."
        ) {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(appState.mcpServers) { server in
                    MCPServerCard(
                        server: server,
                        onDelete: { serverToDelete = server }
                    )
                }
            }
        }
    }

    // MARK: - Marketplace Tab

    private var marketplaceContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                TextField(L10n.string("Search marketplace…"), text: $marketplaceQuery)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 340)
                    .onSubmit {
                        Task { await searchMarketplace() }
                    }

                Button {
                    Task { await searchMarketplace() }
                } label: {
                    if isSearchingMarketplace {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(L10n.string("Searching…"))
                        }
                    } else {
                        Label(L10n.string("Search"), systemImage: "magnifyingglass")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(isSearchingMarketplace)
            }

            if appState.mcpMarketplaceItems.isEmpty {
                HermesSurfacePanel {
                    ContentUnavailableView(
                        L10n.string("No Results"),
                        systemImage: "magnifyingglass",
                        description: Text(L10n.string("Enter a search term to browse available MCP servers."))
                    )
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
            } else {
                HermesSurfacePanel(
                    title: "Marketplace Results",
                    subtitle: "\(appState.mcpMarketplaceItems.count) result(s)"
                ) {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(appState.mcpMarketplaceItems) { item in
                            MCPMarketplaceCard(item: item) {
                                Task { await installMarketplaceItem(item) }
                            }
                        }
                    }
                }
            }
        }
    }

    private func searchMarketplace() async {
        isSearchingMarketplace = true
        await appState.searchMCPMarketplace(query: marketplaceQuery)
        isSearchingMarketplace = false
    }

    private func installMarketplaceItem(_ item: MCPMarketplaceItem) async {
        guard let installCommand = item.installCommand, !installCommand.isEmpty else { return }
        let parts = installCommand.split(separator: " ").map(String.init)
        guard !parts.isEmpty else { return }
        let server = MCPServerCreate(
            name: item.name,
            command: parts[0],
            args: Array(parts.dropFirst()),
            enabled: true
        )
        await appState.addMCPServer(server)
    }
}

// MARK: - MCP Server Card

private struct MCPServerCard: View {
    let server: MCPServer
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(server.name)
                        .font(.headline)

                    if let trustLevel = server.trustLevel {
                        HermesBadge(
                            text: trustLevel.capitalized,
                            tint: trustLevelColor(trustLevel)
                        )
                    }
                }

                Text(([server.command] + server.args).joined(separator: " "))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Button {
                onDelete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.red)
            .help(L10n.string("Remove server"))
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
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(L10n.string("Remove"), systemImage: "trash")
            }
        }
    }

    private func trustLevelColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "official": return .blue
        case "community": return .green
        default: return .orange
        }
    }
}

// MARK: - MCP Marketplace Card

private struct MCPMarketplaceCard: View {
    let item: MCPMarketplaceItem
    let onInstall: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(item.name)
                        .font(.headline)

                    HermesBadge(
                        text: item.trustLevel.capitalized,
                        tint: trustLevelColor(item.trustLevel)
                    )

                    if let source = item.source, !source.isEmpty {
                        HermesBadge(text: source, tint: .secondary)
                    }
                }

                Text(item.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if let installCommand = item.installCommand, !installCommand.isEmpty {
                    Text(installCommand)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 12)

            if item.installCommand != nil {
                Button {
                    onInstall()
                } label: {
                    Label(L10n.string("Install"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
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
    }

    private func trustLevelColor(_ level: String) -> Color {
        switch level.lowercased() {
        case "official": return .blue
        case "community": return .green
        default: return .orange
        }
    }
}

// MARK: - Add MCP Server Sheet

struct AddMCPServerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let onAdd: (MCPServerCreate) -> Void

    @State private var name = ""
    @State private var command = ""
    @State private var argsText = ""

    private var parsedArgs: [String] {
        argsText
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.string("Add MCP Server"))
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 14) {
                labeledField(title: "Name") {
                    TextField(L10n.string("Server name…"), text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField(title: "Command") {
                    TextField(L10n.string("e.g. npx or /usr/local/bin/mcp-server"), text: $command)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                labeledField(title: "Arguments") {
                    TextField(L10n.string("Space-separated arguments…"), text: $argsText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
            }

            HStack {
                Spacer()

                Button(L10n.string("Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.string("Add Server")) {
                    let server = MCPServerCreate(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        command: command.trimmingCharacters(in: .whitespacesAndNewlines),
                        args: parsedArgs,
                        enabled: true
                    )
                    onAdd(server)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(title))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
