import Foundation

extension DashboardAPIService {

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
