import Foundation

extension AppState {
    // MARK: - MCP Servers

    func loadMCPServers() async {
        guard dashboardAPIAvailable else { return }
        if isLoadingMCP { return }

        isLoadingMCP = true
        mcpError = nil

        do {
            let servers = try await dashboardAPIService.fetchMCPServers()
            mcpServers = servers
            isLoadingMCP = false
        } catch {
            isLoadingMCP = false
            mcpError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load MCP servers"))
        }
    }

    func searchMCPMarketplace(query: String) async {
        guard dashboardAPIAvailable else { return }

        do {
            let items = try await dashboardAPIService.searchMCPHub(query: query)
            mcpMarketplaceItems = items
        } catch {
            mcpError = error.localizedDescription
            setStatusMessage(L10n.string("MCP marketplace search failed: %@", error.localizedDescription))
        }
    }

    func addMCPServer(_ server: MCPServerCreate) async {
        guard dashboardAPIAvailable else { return }

        do {
            let created = try await dashboardAPIService.createMCPServer(server)
            mcpServers.append(created)
            setStatusMessage(L10n.string("%@ added", server.name))
        } catch {
            mcpError = error.localizedDescription
            setStatusMessage(error.localizedDescription)
        }
    }

    func deleteMCPServer(id: String) async {
        guard dashboardAPIAvailable else { return }

        do {
            try await dashboardAPIService.deleteMCPServer(id: id)
            mcpServers.removeAll { $0.id == id }
            setStatusMessage(L10n.string("Server removed"))
        } catch {
            mcpError = error.localizedDescription
            setStatusMessage(error.localizedDescription)
        }
    }
}
