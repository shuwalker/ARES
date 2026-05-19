import Foundation

extension DashboardAPIService {

    // MARK: - Plugins

    /// GET /api/dashboard/plugins/hub
    func getPluginsHub() async throws -> PluginsHubResponse {
        let data = try await authenticatedGet(path: "api/dashboard/plugins/hub")
        return try JSONDecoder().decode(PluginsHubResponse.self, from: data)
    }

    /// POST /api/dashboard/agent-plugins/install
    func installAgentPlugin(identifier: String, force: Bool, enable: Bool) async throws -> AgentPluginInstallResponse {
        let request = AgentPluginInstallRequest(identifier: identifier, force: force, enable: enable)
        let payload = try JSONEncoder().encode(request)
        let data = try await authenticatedPost(path: "api/dashboard/agent-plugins/install", body: payload)
        return try JSONDecoder().decode(AgentPluginInstallResponse.self, from: data)
    }

    /// POST /api/dashboard/agent-plugins/{name}/enable
    func enableAgentPlugin(name: String) async throws -> AgentPluginToggleResponse {
        let data = try await authenticatedPost(path: "api/dashboard/agent-plugins/\(name)/enable", body: Data())
        return try JSONDecoder().decode(AgentPluginToggleResponse.self, from: data)
    }

    /// POST /api/dashboard/agent-plugins/{name}/disable
    func disableAgentPlugin(name: String) async throws -> AgentPluginToggleResponse {
        let data = try await authenticatedPost(path: "api/dashboard/agent-plugins/\(name)/disable", body: Data())
        return try JSONDecoder().decode(AgentPluginToggleResponse.self, from: data)
    }

    /// POST /api/dashboard/agent-plugins/{name}/update
    func updateAgentPlugin(name: String) async throws -> AgentPluginUpdateResponse {
        let data = try await authenticatedPost(path: "api/dashboard/agent-plugins/\(name)/update", body: Data())
        return try JSONDecoder().decode(AgentPluginUpdateResponse.self, from: data)
    }

    /// DELETE /api/dashboard/agent-plugins/{name}
    func removeAgentPlugin(name: String) async throws -> AgentPluginToggleResponse {
        let data = try await authenticatedDelete(path: "api/dashboard/agent-plugins/\(name)")
        return try JSONDecoder().decode(AgentPluginToggleResponse.self, from: data)
    }

    /// PUT /api/dashboard/plugin-providers
    func savePluginProviders(memoryProvider: String, contextEngine: String) async throws -> SavePluginProvidersResponse {
        let body: [String: String] = [
            "memory_provider": memoryProvider,
            "context_engine": contextEngine
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        let data = try await authenticatedPut(path: "api/dashboard/plugin-providers", body: payload)
        return try JSONDecoder().decode(SavePluginProvidersResponse.self, from: data)
    }

    /// POST /api/dashboard/plugins/rescan
    func rescanPlugins() async throws -> RescanPluginsResponse {
        let data = try await authenticatedPost(path: "api/dashboard/plugins/rescan", body: Data())
        return try JSONDecoder().decode(RescanPluginsResponse.self, from: data)
    }
}
