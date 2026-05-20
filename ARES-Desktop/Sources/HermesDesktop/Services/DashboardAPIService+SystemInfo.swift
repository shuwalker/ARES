import Foundation

extension DashboardAPIService {

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

    // MARK: - Dashboard

    /// GET /api/dashboard/overview?period={n}
    func fetchDashboardOverview(period: Int = 14) async throws -> DashboardOverview {
        let path = "api/dashboard/overview?period=\(period)"
        let data = try await authenticatedGet(path: path)
        return try JSONDecoder().decode(DashboardOverview.self, from: data)
    }

    // MARK: - Session Status

    /// GET /api/session-status
    func fetchSessionStatus() async throws -> SessionStatusResponse {
        let data = try await authenticatedGet(path: "api/session-status")
        return try JSONDecoder().decode(SessionStatusResponse.self, from: data)
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
}
