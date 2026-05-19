import Foundation

extension DashboardAPIService {

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
}
