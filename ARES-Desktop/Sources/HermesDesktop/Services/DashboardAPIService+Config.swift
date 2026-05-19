import Foundation

extension DashboardAPIService {

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
}
