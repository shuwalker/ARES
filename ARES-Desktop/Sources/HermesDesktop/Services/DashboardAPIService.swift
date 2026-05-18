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

    /// GET /api/analytics/models?days=7
    func fetchModelsAnalytics(days: Int = 30) async throws -> ModelsAnalyticsResponse {
        let path = "api/analytics/models?days=\(days)"
        let data = try await authenticatedGet(path: path)
        return try JSONDecoder().decode(ModelsAnalyticsResponse.self, from: data)
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw TransportError.remoteFailure("HTTP \(statusCode): \(errorBody)")
        }
    }
}