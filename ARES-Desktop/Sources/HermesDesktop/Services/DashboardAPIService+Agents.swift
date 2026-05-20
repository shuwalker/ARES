import Foundation

extension DashboardAPIService {

    // MARK: - Sessions

    /// PATCH /api/sessions/{id} — rename a session by updating its title.
    /// This is a best-effort call: if the endpoint is unavailable the error is propagated
    /// to the caller, which may choose to swallow it gracefully.
    func renameSession(id: String, title: String) async throws {
        try await ensureSessionToken()
        let path = "api/sessions/\(id)"
        let payload = try JSONEncoder().encode(["title": title])

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
    @discardableResult
    func swarmDispatch(worker: String, prompt: String, missionId: String? = nil) async throws -> Data {
        let request = SwarmDispatchRequest(worker: worker, prompt: prompt, missionId: missionId)
        let payload = try JSONEncoder().encode(request)
        return try await authenticatedPost(path: "api/swarm-dispatch", body: payload)
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

    /// POST /api/swarm-chat — chat with entire swarm; returns assistant reply or empty string
    func swarmChat(message: String) async throws -> String {
        let body: [String: String] = ["message": message]
        let payload = try JSONSerialization.data(withJSONObject: body)
        let data = try await authenticatedPost(path: "api/swarm-chat", body: payload)
        let decoded = try? JSONDecoder().decode(SwarmDirectChatResponse.self, from: data)
        return decoded?.assistantReply ?? String(data: data, encoding: .utf8) ?? ""
    }

    /// POST /api/swarm-direct-chat — chat with a specific worker; returns assistant reply or empty string
    func swarmDirectChat(worker: String, message: String) async throws -> String {
        let request = SwarmDirectChatRequest(worker: worker, message: message)
        let payload = try JSONEncoder().encode(request)
        let data = try await authenticatedPost(path: "api/swarm-direct-chat", body: payload)
        let decoded = try? JSONDecoder().decode(SwarmDirectChatResponse.self, from: data)
        return decoded?.assistantReply ?? String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Operations

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

    // MARK: - Crew Status

    /// GET /api/claude-config — agents defined in workspace config (returns raw JSON)
    func fetchClaudeConfig() async throws -> Data {
        try await authenticatedGet(path: "api/claude-config")
    }

    /// GET /api/sessions — recent session activity (returns raw JSON)
    func fetchSessionsRaw() async throws -> Data {
        try await authenticatedGet(path: "api/sessions")
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

    // MARK: - Profiles

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

    // MARK: - Keys (System Controls)

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

    // MARK: - System

    /// GET /api/actions/{name}/status?lines=200
    func getActionStatus(name: String, lines: Int = 200) async throws -> ActionStatusResponse {
        let path = "api/actions/\(name)/status?lines=\(lines)"
        let data = try await authenticatedGet(path: path)
        return try JSONDecoder().decode(ActionStatusResponse.self, from: data)
    }

    // MARK: - Jobs

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

    // MARK: - MCP

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
}
