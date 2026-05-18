import Foundation

/// Service that calls the Hermes dashboard web API (port 9119) using HTTPTransport.
/// This is intended for local connections where Hermes is running on the same machine.
final class DashboardAPIService: @unchecked Sendable {
    private let httpTransport: HTTPTransport
    let baseURL: URL

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

    // MARK: - Config

    /// Fetches the current configuration and optional schema.
    func fetchConfig() async throws -> ConfigResponse {
        let data = try await httpTransport.get(
            path: "api/config",
            baseURL: baseURL,
            apiKey: nil
        )
        return try JSONDecoder().decode(ConfigResponse.self, from: data)
    }

    /// Updates a single configuration key.
    /// - Parameters:
    ///   - key: The configuration key path (dot-separated or plain key).
    ///   - value: The new string value.
    func updateConfig(key: String, value: String) async throws {
        let body: [String: String] = [
            "key": key,
            "value": value
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await httpTransport.post(
            path: "api/config",
            body: payload,
            baseURL: baseURL,
            apiKey: nil
        )
    }

    /// Fetches the raw YAML configuration.
    func fetchRawConfig() async throws -> String {
        let data = try await httpTransport.get(
            path: "api/config/raw",
            baseURL: baseURL,
            apiKey: nil
        )
        guard let yaml = String(data: data, encoding: .utf8) else {
            throw TransportError.invalidResponse("Unable to decode raw config as UTF-8")
        }
        return yaml
    }

    /// Updates the raw YAML configuration.
    /// - Parameter yaml: The complete YAML string to send.
    func updateRawConfig(yaml: String) async throws {
        let body: [String: String] = [
            "yaml": yaml
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await httpTransport.post(
            path: "api/config/raw",
            body: payload,
            baseURL: baseURL,
            apiKey: nil
        )
    }

    // MARK: - Environment

    /// Fetches the environment variables.
    func fetchEnv() async throws -> EnvResponse {
        let data = try await httpTransport.get(
            path: "api/env",
            baseURL: baseURL,
            apiKey: nil
        )
        return try JSONDecoder().decode(EnvResponse.self, from: data)
    }

    /// Updates environment variables.
    /// - Parameter entries: A dictionary of key/value pairs.
    func updateEnv(entries: [String: String]) async throws {
        let payload = try JSONSerialization.data(withJSONObject: entries)
        _ = try await httpTransport.post(
            path: "api/env",
            body: payload,
            baseURL: baseURL,
            apiKey: nil
        )
    }

    // MARK: - Logs

    /// Reads the specified log file.
    /// - Parameters:
    ///   - file: The log filename (e.g. "hermes.log").
    ///   - level: Minimum log level filter.
    ///   - lines: Maximum number of lines to return.
    func fetchLogs(file: String, level: String, lines: Int) async throws -> LogsResponse {
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

        let data = try await httpTransport.get(
            path: path,
            baseURL: baseURL,
            apiKey: nil
        )
        return try JSONDecoder().decode(LogsResponse.self, from: data)
    }

    // MARK: - Models

    /// Fetches available models and the currently selected model.
    func fetchModels() async throws -> ModelsResponse {
        let data = try await httpTransport.get(
            path: "api/models",
            baseURL: baseURL,
            apiKey: nil
        )
        return try JSONDecoder().decode(ModelsResponse.self, from: data)
    }

    /// Sets the active model.
    /// - Parameter model: The model identifier.
    func setModel(_ model: String) async throws {
        let body: [String: String] = [
            "model": model
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await httpTransport.post(
            path: "api/models",
            body: payload,
            baseURL: baseURL,
            apiKey: nil
        )
    }

    /// Fetches analytics for all models.
    func fetchModelsAnalytics() async throws -> ModelsAnalyticsResponse {
        let data = try await httpTransport.get(
            path: "api/models/analytics",
            baseURL: baseURL,
            apiKey: nil
        )
        return try JSONDecoder().decode(ModelsAnalyticsResponse.self, from: data)
    }

    // MARK: - Profiles

    /// Lists all Hermes profiles.
    func fetchProfiles() async throws -> ProfilesResponse {
        let data = try await httpTransport.get(
            path: "api/profiles",
            baseURL: baseURL,
            apiKey: nil
        )
        return try JSONDecoder().decode(ProfilesResponse.self, from: data)
    }

    /// Creates a new Hermes profile.
    /// - Parameter name: The name for the new profile.
    func createProfile(name: String) async throws {
        let body: [String: String] = [
            "name": name
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await httpTransport.post(
            path: "api/profiles",
            body: payload,
            baseURL: baseURL,
            apiKey: nil
        )
    }

    /// Deletes a Hermes profile.
    /// - Parameter name: The profile name to delete.
    func deleteProfile(name: String) async throws {
        let body: [String: String] = [
            "name": name
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await httpTransport.post(
            path: "api/profiles/delete",
            body: payload,
            baseURL: baseURL,
            apiKey: nil
        )
    }

    // MARK: - Status

    /// Fetches the overall Hermes status.
    func fetchStatus() async throws -> StatusResponse {
        let data = try await httpTransport.get(
            path: "api/status",
            baseURL: baseURL,
            apiKey: nil
        )
        return try JSONDecoder().decode(StatusResponse.self, from: data)
    }
}
