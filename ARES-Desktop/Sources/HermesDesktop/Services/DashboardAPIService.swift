import Foundation

/// Service that calls the Hermes dashboard web API (port 9119) using HTTPTransport.
/// Authenticates via the ephemeral session token injected into the dashboard SPA HTML.
final class DashboardAPIService: @unchecked Sendable {
    private let httpTransport: HTTPTransport
    var baseURL: URL

    /// Ephemeral session token obtained from the dashboard HTML.
    /// Regenerated on each server start; must be fetched before making authenticated requests.
    private var sessionToken: String?

    /// Creates a new dashboard API service.
    /// - Parameters:
    ///   - httpTransport: The transport layer for making HTTP requests.
    ///   - baseURL: The root URL of the dashboard API. Defaults to `http://localhost:9119`.
    init(
        httpTransport: HTTPTransport,
        baseURL: URL = URL(string: "http://localhost:9119")!
    ) {
        self.httpTransport = httpTransport
        self.baseURL = baseURL
    }

    // MARK: - Authentication

    /// Fetches the session token from the dashboard HTML if we don't have one yet.
    private func ensureSessionToken() async throws {
        guard sessionToken == nil else { return }

        let data = try await httpTransport.get(
            path: "/",
            baseURL: baseURL,
            apiKey: nil
        )

        guard let html = String(data: data, encoding: .utf8) else {
            throw TransportError.localFailure("Dashboard HTML was not valid UTF-8")
        }

        // Extract: window.__HERMES_SESSION_TOKEN__="...value...";
        let pattern = #"__HERMES_SESSION_TOKEN__=\\"([^"]+)\\""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let tokenRange = Range(match.range(at: 1), in: html) else {
            // If no token found, the dashboard might be running without auth.
            // Leave sessionToken nil — requests will try without token.
            return
        }

        sessionToken = String(html[tokenRange])
    }

    private func authenticatedGet(path: String) async throws -> Data {
        try await ensureSessionToken()

        // Try with session token header first
        if let token = sessionToken {
            do {
                return try await httpTransport.getWithHeaders(
                    path: path,
                    baseURL: baseURL,
                    headers: ["X-Hermes-Session-Token": token]
                )
            } catch let error as TransportError {
                // If we get 401, the token may have expired (server restart).
                // Clear it and retry.
                if error.localizedDescription.contains("401") || error.localizedDescription.contains("Unauthorized") {
                    sessionToken = nil
                    try await ensureSessionToken()
                    if let newToken = sessionToken {
                        return try await httpTransport.getWithHeaders(
                            path: path,
                            baseURL: baseURL,
                            headers: ["X-Hermes-Session-Token": newToken]
                        )
                    }
                }
                throw error
            }
        }

        // No token available — try unauthenticated (some endpoints don't require auth)
        return try await httpTransport.get(path: path, baseURL: baseURL, apiKey: nil)
    }

    private func authenticatedPost(path: String, body: Data) async throws -> Data {
        try await ensureSessionToken()

        if let token = sessionToken {
            do {
                return try await httpTransport.postWithHeaders(
                    path: path,
                    body: body,
                    baseURL: baseURL,
                    headers: ["X-Hermes-Session-Token": token]
                )
            } catch let error as TransportError {
                if error.localizedDescription.contains("401") || error.localizedDescription.contains("Unauthorized") {
                    sessionToken = nil
                    try await ensureSessionToken()
                    if let newToken = sessionToken {
                        return try await httpTransport.postWithHeaders(
                            path: path,
                            body: body,
                            baseURL: baseURL,
                            headers: ["X-Hermes-Session-Token": newToken]
                        )
                    }
                }
                throw error
            }
        }

        return try await httpTransport.post(path: path, body: body, baseURL: baseURL, apiKey: nil)
    }

    private func authenticatedPut(path: String, body: Data) async throws -> Data {
        try await ensureSessionToken()

        if let token = sessionToken {
            do {
                return try await httpTransport.putWithHeaders(
                    path: path,
                    body: body,
                    baseURL: baseURL,
                    headers: ["X-Hermes-Session-Token": token]
                )
            } catch let error as TransportError {
                if error.localizedDescription.contains("401") || error.localizedDescription.contains("Unauthorized") {
                    sessionToken = nil
                    try await ensureSessionToken()
                    if let newToken = sessionToken {
                        return try await httpTransport.putWithHeaders(
                            path: path,
                            body: body,
                            baseURL: baseURL,
                            headers: ["X-Hermes-Session-Token": newToken]
                        )
                    }
                }
                throw error
            }
        }

        return try await httpTransport.put(path: path, body: body, baseURL: baseURL, apiKey: nil)
    }

    private func authenticatedDelete(path: String) async throws -> Data {
        try await ensureSessionToken()

        if let token = sessionToken {
            do {
                return try await httpTransport.deleteWithHeaders(
                    path: path,
                    baseURL: baseURL,
                    headers: ["X-Hermes-Session-Token": token]
                )
            } catch let error as TransportError {
                if error.localizedDescription.contains("401") || error.localizedDescription.contains("Unauthorized") {
                    sessionToken = nil
                    try await ensureSessionToken()
                    if let newToken = sessionToken {
                        return try await httpTransport.deleteWithHeaders(
                            path: path,
                            baseURL: baseURL,
                            headers: ["X-Hermes-Session-Token": newToken]
                        )
                    }
                }
                throw error
            }
        }

        return try await httpTransport.delete(path: path, baseURL: baseURL, apiKey: nil)
    }

    // MARK: - Status (public, no auth needed)

    func fetchStatus() async throws -> StatusResponse {
        let data = try await httpTransport.get(
            path: "api/status",
            baseURL: baseURL,
            apiKey: nil
        )
        return try JSONDecoder().decode(StatusResponse.self, from: data)
    }

    // MARK: - Config

    /// GET /api/config — returns flat config dict
    func fetchConfig() async throws -> ConfigResponse {
        let data = try await authenticatedGet(path: "api/config")
        return try JSONDecoder().decode(ConfigResponse.self, from: data)
    }

    /// GET /api/config/schema — returns field definitions
    func fetchConfigSchema() async throws -> ConfigSchemaResponse {
        let data = try await authenticatedGet(path: "api/config/schema")
        return try JSONDecoder().decode(ConfigSchemaResponse.self, from: data)
    }

    /// PUT /api/config — update entire config
    func updateConfig(config: ConfigResponse) async throws {
        let payload = try JSONEncoder().encode(config)
        _ = try await authenticatedPut(path: "api/config", body: payload)
    }

    /// GET /api/config/raw — returns { "yaml": "..." }
    func fetchRawConfig() async throws -> String {
        let data = try await authenticatedGet(path: "api/config/raw")
        struct RawConfigResponse: Decodable { let yaml: String }
        let response = try JSONDecoder().decode(RawConfigResponse.self, from: data)
        return response.yaml
    }

    /// PUT /api/config/raw — update raw YAML config
    func updateRawConfig(yaml: String) async throws {
        let body: [String: String] = ["yaml_text": yaml]
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await authenticatedPut(path: "api/config/raw", body: payload)
    }

    // MARK: - Environment

    /// GET /api/env — returns flat dict of env var info objects
    func fetchEnv() async throws -> EnvResponse {
        let data = try await authenticatedGet(path: "api/env")
        return try JSONDecoder().decode(EnvResponse.self, from: data)
    }

    /// PUT /api/env — set an env var
    func setEnvVar(key: String, value: String) async throws {
        let body: [String: String] = ["key": key, "value": value]
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await authenticatedPut(path: "api/env", body: payload)
    }

    /// POST /api/env/reveal — reveal a masked env value (requires session token)
    func revealEnvVar(key: String) async throws -> String {
        let body: [String: String] = ["key": key]
        let payload = try JSONSerialization.data(withJSONObject: body)
        let data = try await authenticatedPost(path: "api/env/reveal", body: payload)
        struct RevealResponse: Decodable { let value: String }
        let response = try JSONDecoder().decode(RevealResponse.self, from: data)
        return response.value
    }

    // MARK: - Logs

    /// GET /api/logs?file=agent&lines=200&level=ALL
    func fetchLogs(file: String = "agent", level: String = "ALL", lines: Int = 200) async throws -> LogsResponse {
        var components = URLComponents()
        components.path = "api/logs"
        components.queryItems = [
            URLQueryItem(name: "file", value: file),
            URLQueryItem(name: "level", value: level),
            URLQueryItem(name: "lines", value: String(lines))
        ]

        guard let path = components.url?.absoluteString else {
            throw TransportError.localFailure("Failed to construct logs query path")
        }

        let data = try await authenticatedGet(path: path)
        return try JSONDecoder().decode(LogsResponse.self, from: data)
    }

    // MARK: - Models

    /// GET /api/model/info — current active model
    func fetchModelInfo() async throws -> ModelInfoResponse {
        let data = try await authenticatedGet(path: "api/model/info")
        return try JSONDecoder().decode(ModelInfoResponse.self, from: data)
    }

    /// GET /api/model/options — all providers and models
    func fetchModelOptions() async throws -> ModelOptionsResponse {
        let data = try await authenticatedGet(path: "api/model/options")
        return try JSONDecoder().decode(ModelOptionsResponse.self, from: data)
    }

    /// GET /api/model/auxiliary — auxiliary model assignments
    func fetchAuxiliaryModels() async throws -> AuxiliaryModelsResponse {
        let data = try await authenticatedGet(path: "api/model/auxiliary")
        return try JSONDecoder().decode(AuxiliaryModelsResponse.self, from: data)
    }

    /// POST /api/model/set — switch the active model
    func setModel(model: String, provider: String? = nil) async throws {
        let request = ModelSetRequest(model: model, provider: provider)
        let payload = try JSONEncoder().encode(request)
        _ = try await authenticatedPost(path: "api/model/set", body: payload)
    }

    // MARK: - Dashboard Overview (Feature 1)

    /// GET /api/dashboard/overview?period={n}
    func fetchDashboardOverview(period: Int = 14) async throws -> DashboardOverview {
        let path = "api/dashboard/overview?period=\(period)"
        let data = try await authenticatedGet(path: path)
        return try JSONDecoder().decode(DashboardOverview.self, from: data)
    }

    // MARK: - Session Status (Feature 2)

    /// GET /api/session-status
    func fetchSessionStatus() async throws -> SessionStatusResponse {
        let data = try await authenticatedGet(path: "api/session-status")
        return try JSONDecoder().decode(SessionStatusResponse.self, from: data)
    }

    // MARK: - Claude Config PATCH (Feature 3)

    /// PATCH /api/claude-config — partial update of Claude config fields
    func patchClaudeConfig(_ fields: [String: Any]) async throws {
        let payload = try JSONSerialization.data(withJSONObject: fields)
        try await ensureSessionToken()

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/claude-config"))
        urlRequest.httpMethod = "PATCH"
        urlRequest.httpBody = payload
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = sessionToken {
            urlRequest.setValue(token, forHTTPHeaderField: "X-Hermes-Session-Token")
        }

        let (data, response) = try await httpTransport.session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TransportError.remoteFailure("HTTP \(statusCode): \(errorBody)")
        }
    }

    // MARK: - Analytics

    /// GET /api/analytics/usage?days={n}
    func fetchAnalyticsUsage(days: Int = 30) async throws -> AnalyticsResponse {
        let path = "api/analytics/usage?days=\(days)"
        let data = try await authenticatedGet(path: path)
        return try JSONDecoder().decode(AnalyticsResponse.self, from: data)
    }

    /// GET /api/analytics/models?days=7
    func fetchModelsAnalytics(days: Int = 30) async throws -> ModelsAnalyticsResponse {
        let path = "api/analytics/models?days=\(days)"
        let data = try await authenticatedGet(path: path)
        return try JSONDecoder().decode(ModelsAnalyticsResponse.self, from: data)
    }

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

    /// GET /api/profiles
    func fetchProfiles() async throws -> ProfilesResponse {
        let data = try await authenticatedGet(path: "api/profiles")
        return try JSONDecoder().decode(ProfilesResponse.self, from: data)
    }

    /// POST /api/profiles — create a new profile
    func createProfile(name: String) async throws {
        let body: [String: String] = ["name": name]
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await authenticatedPost(path: "api/profiles", body: payload)
    }

    /// DELETE /api/profiles/{name}
    func deleteProfile(name: String) async throws {
        let path = "api/profiles/\(name)"
        // Use a DELETE method
        try await ensureSessionToken()
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "DELETE"
        if let token = sessionToken {
            request.setValue(token, forHTTPHeaderField: "X-Hermes-Session-Token")
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await httpTransport.session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TransportError.remoteFailure("HTTP \(statusCode): \(errorBody)")
        }
    }

    // MARK: - System Controls

    /// POST /api/gateway/restart
    func restartGateway() async throws -> ActionResponse {
        let data = try await authenticatedPost(path: "api/gateway/restart", body: Data())
        return try JSONDecoder().decode(ActionResponse.self, from: data)
    }

    /// POST /api/hermes/update
    func updateHermes() async throws -> ActionResponse {
        let data = try await authenticatedPost(path: "api/hermes/update", body: Data())
        return try JSONDecoder().decode(ActionResponse.self, from: data)
    }

    /// GET /api/actions/{name}/status?lines=200
    func getActionStatus(name: String, lines: Int = 200) async throws -> ActionStatusResponse {
        let path = "api/actions/\(name)/status?lines=\(lines)"
        let data = try await authenticatedGet(path: path)
        return try JSONDecoder().decode(ActionStatusResponse.self, from: data)
    }

    // MARK: - Memory

    /// GET /api/memory
    func fetchMemory() async throws -> MemoryResponse {
        let data = try await authenticatedGet(path: "api/memory")
        return try JSONDecoder().decode(MemoryResponse.self, from: data)
    }

    /// DELETE /api/memory/{id}
    func deleteMemoryEntry(id: String) async throws {
        _ = try await authenticatedDelete(path: "api/memory/\(id)")
    }

    /// PUT /api/memory/{id}
    func updateMemoryEntry(id: String, content: String) async throws {
        let body: [String: String] = ["content": content]
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await authenticatedPut(path: "api/memory/\(id)", body: payload)
    }

    // MARK: - Tools

    /// GET /api/tools
    func fetchTools() async throws -> ToolsResponse {
        let data = try await authenticatedGet(path: "api/tools")
        return try JSONDecoder().decode(ToolsResponse.self, from: data)
    }

    /// POST /api/tools/{name}/enable or /api/tools/{name}/disable
    func setToolEnabled(name: String, enabled: Bool) async throws {
        let action = enabled ? "enable" : "disable"
        _ = try await authenticatedPost(path: "api/tools/\(name)/\(action)", body: Data())
    }

    // MARK: - Tool Approvals

    /// GET /api/approvals — returns pending tool approval requests
    func fetchPendingApprovals() async throws -> [ToolApprovalRequest] {
        let data = try await authenticatedGet(path: "api/approvals")
        return try JSONDecoder().decode([ToolApprovalRequest].self, from: data)
    }

    /// POST /api/approvals/{id}/approve — approve a pending tool call
    func approveToolCall(id: String) async throws {
        _ = try await authenticatedPost(path: "api/approvals/\(id)/approve", body: Data())
    }

    /// POST /api/approvals/{id}/deny — deny a pending tool call
    func denyToolCall(id: String) async throws {
        _ = try await authenticatedPost(path: "api/approvals/\(id)/deny", body: Data())
    }

    // MARK: - Kanban plugin HTTP API

    /// PATCH /api/plugins/kanban/tasks/{taskID} — move task to a new status column
    func kanbanMoveTask(boardSlug: String, taskID: String, statusRawValue: String) async throws {
        let body: [String: String] = ["status": statusRawValue, "board": boardSlug]
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await authenticatedPost(path: "api/plugins/kanban/tasks/\(taskID)", body: payload)
    }

    /// POST /api/plugins/kanban/tasks/{task_id}/decompose
    /// LLM decomposes the task into subtasks on the given board.
    func kanbanDecomposeTask(taskID: String, boardSlug: String) async throws {
        let body: [String: String] = ["board": boardSlug]
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await authenticatedPost(path: "api/plugins/kanban/tasks/\(taskID)/decompose", body: payload)
    }

    /// GET /api/plugins/kanban/tasks/{task_id}/log?board={boardSlug}
    /// Returns the worker stdout/stderr log text for the given task.
    func kanbanGetTaskLog(taskID: String, boardSlug: String) async throws -> String {
        let path = "api/plugins/kanban/tasks/\(taskID)/log?board=\(boardSlug)"
        let data = try await authenticatedGet(path: path)
        struct LogResponse: Decodable {
            let log: String?
            let text: String?
        }
        if let response = try? JSONDecoder().decode(LogResponse.self, from: data) {
            return response.log ?? response.text ?? ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// GET /api/plugins/kanban/orchestration
    /// Returns the current orchestration configuration.
    func kanbanGetOrchestration() async throws -> KanbanOrchestrationConfig {
        let data = try await authenticatedGet(path: "api/plugins/kanban/orchestration")
        return try JSONDecoder().decode(KanbanOrchestrationConfig.self, from: data)
    }

    /// PUT /api/plugins/kanban/orchestration
    /// Updates the orchestration configuration.
    func kanbanUpdateOrchestration(_ config: KanbanOrchestrationConfig) async throws {
        let payload = try JSONEncoder().encode(config)
        _ = try await authenticatedPut(path: "api/plugins/kanban/orchestration", body: payload)
    }

    /// POST /api/plugins/kanban/tasks/bulk
    /// Bulk-patches a list of tasks (e.g. status change).
    func kanbanBulkUpdateTasks(taskIDs: [String], status: KanbanTaskStatus, boardSlug: String) async throws {
        let body: [String: Any] = [
            "board": boardSlug,
            "task_ids": taskIDs,
            "patch": ["status": status.rawValue]
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await authenticatedPost(path: "api/plugins/kanban/tasks/bulk", body: payload)
    }

    /// PATCH /api/plugins/kanban/profiles/{profile_name}
    /// Updates a profile's description field.
    func kanbanUpdateProfileDescription(profileName: String, description: String) async throws {
        try await ensureSessionToken()
        let path = "api/plugins/kanban/profiles/\(profileName)"
        let body: [String: String] = ["description": description]
        let payload = try JSONSerialization.data(withJSONObject: body)

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
        urlRequest.httpMethod = "PATCH"
        urlRequest.httpBody = payload
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = sessionToken {
            urlRequest.setValue(token, forHTTPHeaderField: "X-Hermes-Session-Token")
        }

        let (data, response) = try await httpTransport.session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TransportError.remoteFailure("HTTP \(statusCode): \(errorBody)")
        }
    }

    /// POST /api/plugins/kanban/profiles/{profile_name}/describe-auto
    /// LLM auto-generates a profile description and returns it.
    func kanbanAutoDescribeProfile(profileName: String) async throws -> String {
        let data = try await authenticatedPost(
            path: "api/plugins/kanban/profiles/\(profileName)/describe-auto",
            body: Data()
        )
        struct DescribeResponse: Decodable {
            let description: String?
            let text: String?
        }
        if let response = try? JSONDecoder().decode(DescribeResponse.self, from: data) {
            return response.description ?? response.text ?? ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Claude Jobs (/api/claude-jobs)

    /// GET /api/claude-jobs — list all dashboard cron jobs
    func fetchClaudeJobs() async throws -> [DashboardCronJob] {
        let data = try await authenticatedGet(path: "api/claude-jobs")
        return try JSONDecoder().decode([DashboardCronJob].self, from: data)
    }

    /// POST /api/claude-jobs — create a new dashboard cron job
    func createClaudeJob(_ job: DashboardCronJobCreate) async throws -> DashboardCronJob {
        let payload = try JSONEncoder().encode(job)
        let data = try await authenticatedPost(path: "api/claude-jobs", body: payload)
        return try JSONDecoder().decode(DashboardCronJob.self, from: data)
    }

    /// GET /api/claude-jobs/{id} — fetch a single dashboard cron job
    func fetchClaudeJob(id: String) async throws -> DashboardCronJob {
        let data = try await authenticatedGet(path: "api/claude-jobs/\(id)")
        return try JSONDecoder().decode(DashboardCronJob.self, from: data)
    }

    /// PATCH /api/claude-jobs/{id} — update/pause/resume a dashboard cron job
    func patchClaudeJob(id: String, patch: DashboardCronJobPatch) async throws -> DashboardCronJob {
        try await ensureSessionToken()
        let path = "api/claude-jobs/\(id)"
        let payload = try JSONEncoder().encode(patch)

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent(path))
        urlRequest.httpMethod = "PATCH"
        urlRequest.httpBody = payload
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = sessionToken {
            urlRequest.setValue(token, forHTTPHeaderField: "X-Hermes-Session-Token")
        }

        let (data, response) = try await httpTransport.session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TransportError.remoteFailure("HTTP \(statusCode): \(errorBody)")
        }
        return try JSONDecoder().decode(DashboardCronJob.self, from: data)
    }

    /// DELETE /api/claude-jobs/{id} — delete a dashboard cron job
    func deleteClaudeJob(id: String) async throws {
        _ = try await authenticatedDelete(path: "api/claude-jobs/\(id)")
    }

    // MARK: - MCP Servers (/api/mcp)

    /// GET /api/mcp — list all configured MCP servers
    func fetchMCPServers() async throws -> [MCPServer] {
        let data = try await authenticatedGet(path: "api/mcp")
        return try JSONDecoder().decode([MCPServer].self, from: data)
    }

    /// POST /api/mcp — add a new MCP server
    func createMCPServer(_ server: MCPServerCreate) async throws -> MCPServer {
        let payload = try JSONEncoder().encode(server)
        let data = try await authenticatedPost(path: "api/mcp", body: payload)
        return try JSONDecoder().decode(MCPServer.self, from: data)
    }

    /// PATCH /api/mcp — update an existing MCP server (send id + patch fields)
    func patchMCPServer(id: String, patch: MCPServerPatch) async throws -> MCPServer {
        try await ensureSessionToken()
        var dict: [String: Any] = ["id": id]
        if let enabled = patch.enabled { dict["enabled"] = enabled }
        let payload = try JSONSerialization.data(withJSONObject: dict)

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/mcp"))
        urlRequest.httpMethod = "PATCH"
        urlRequest.httpBody = payload
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = sessionToken {
            urlRequest.setValue(token, forHTTPHeaderField: "X-Hermes-Session-Token")
        }

        let (data, response) = try await httpTransport.session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TransportError.remoteFailure("HTTP \(statusCode): \(errorBody)")
        }
        return try JSONDecoder().decode(MCPServer.self, from: data)
    }

    /// DELETE /api/mcp — remove an MCP server by id
    func deleteMCPServer(id: String) async throws {
        try await ensureSessionToken()
        let body: [String: String] = ["id": id]
        let payload = try JSONSerialization.data(withJSONObject: body)

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/mcp"))
        urlRequest.httpMethod = "DELETE"
        urlRequest.httpBody = payload
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = sessionToken {
            urlRequest.setValue(token, forHTTPHeaderField: "X-Hermes-Session-Token")
        }

        let (data, response) = try await httpTransport.session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TransportError.remoteFailure("HTTP \(statusCode): \(errorBody)")
        }
    }

    /// GET /api/mcp/hub?q={query} — marketplace search
    func searchMCPHub(query: String) async throws -> [MCPMarketplaceItem] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let data = try await authenticatedGet(path: "api/mcp/hub?q=\(encodedQuery)")
        return try JSONDecoder().decode([MCPMarketplaceItem].self, from: data)
    }

    // MARK: - Swarm

    /// GET /api/swarm-runtime — active worker processes + terminal sessions + status
    func fetchSwarmRuntime() async throws -> Data {
        try await authenticatedGet(path: "api/swarm-runtime")
    }

    /// GET /api/swarm-roster — worker definitions: name, role, capabilities
    func fetchSwarmRoster() async throws -> [SwarmWorker] {
        let data = try await authenticatedGet(path: "api/swarm-roster")
        return try JSONDecoder().decode([SwarmWorker].self, from: data)
    }

    /// GET /api/swarm-missions — task assignments and progress
    func fetchSwarmMissions() async throws -> [SwarmMission] {
        let data = try await authenticatedGet(path: "api/swarm-missions")
        return try JSONDecoder().decode([SwarmMission].self, from: data)
    }

    /// GET /api/swarm-health — system diagnostics
    func fetchSwarmHealth() async throws -> SwarmHealth {
        let data = try await authenticatedGet(path: "api/swarm-health")
        return try JSONDecoder().decode(SwarmHealth.self, from: data)
    }

    /// POST /api/swarm-dispatch — send work to a worker
    func swarmDispatch(worker: String, prompt: String, missionId: String? = nil) async throws {
        let request = SwarmDispatchRequest(worker: worker, prompt: prompt, missionId: missionId)
        let payload = try JSONEncoder().encode(request)
        _ = try await authenticatedPost(path: "api/swarm-dispatch", body: payload)
    }

    /// GET /api/swarm-kanban — kanban cards
    func fetchSwarmKanban() async throws -> [SwarmKanbanCard] {
        let data = try await authenticatedGet(path: "api/swarm-kanban")
        return try JSONDecoder().decode([SwarmKanbanCard].self, from: data)
    }

    /// POST /api/swarm-kanban — create a new kanban card
    func createSwarmKanbanCard(_ card: SwarmKanbanCard) async throws -> SwarmKanbanCard {
        let payload = try JSONEncoder().encode(card)
        let data = try await authenticatedPost(path: "api/swarm-kanban", body: payload)
        return try JSONDecoder().decode(SwarmKanbanCard.self, from: data)
    }

    /// PATCH /api/swarm-kanban — update an existing kanban card
    func updateSwarmKanbanCard(_ card: SwarmKanbanCard) async throws {
        try await ensureSessionToken()
        let payload = try JSONEncoder().encode(card)

        var urlRequest = URLRequest(url: baseURL.appendingPathComponent("api/swarm-kanban"))
        urlRequest.httpMethod = "PATCH"
        urlRequest.httpBody = payload
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = sessionToken {
            urlRequest.setValue(token, forHTTPHeaderField: "X-Hermes-Session-Token")
        }

        let (data, response) = try await httpTransport.session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TransportError.remoteFailure("HTTP \(statusCode): \(errorBody)")
        }
    }

    /// GET /api/swarm-reports — mission report aggregation
    func fetchSwarmReports() async throws -> [SwarmReport] {
        let data = try await authenticatedGet(path: "api/swarm-reports")
        return try JSONDecoder().decode([SwarmReport].self, from: data)
    }

    /// GET /api/swarm-memory — worker memory files
    func fetchSwarmMemory() async throws -> [SwarmMemoryFile] {
        let data = try await authenticatedGet(path: "api/swarm-memory")
        return try JSONDecoder().decode([SwarmMemoryFile].self, from: data)
    }

    /// POST /api/swarm-lifecycle — trigger lifecycle action
    func swarmLifecycle(action: String, worker: String? = nil) async throws {
        let request = SwarmLifecycleRequest(action: action, worker: worker)
        let payload = try JSONEncoder().encode(request)
        _ = try await authenticatedPost(path: "api/swarm-lifecycle", body: payload)
    }

    /// POST /api/swarm-chat — chat with entire swarm
    func swarmChat(message: String) async throws {
        let body: [String: String] = ["message": message]
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await authenticatedPost(path: "api/swarm-chat", body: payload)
    }

    /// POST /api/swarm-direct-chat — chat with a specific worker
    func swarmDirectChat(worker: String, message: String) async throws {
        let request = SwarmDirectChatRequest(worker: worker, message: message)
        let payload = try JSONEncoder().encode(request)
        _ = try await authenticatedPost(path: "api/swarm-direct-chat", body: payload)
    }

    // MARK: - Operations / Crew Status

    /// GET /api/claude-config — agents defined in workspace config (returns raw JSON)
    func fetchClaudeConfig() async throws -> Data {
        try await authenticatedGet(path: "api/claude-config")
    }

    /// GET /api/sessions — recent session activity (returns raw JSON)
    func fetchSessionsRaw() async throws -> Data {
        try await authenticatedGet(path: "api/sessions")
    }
}