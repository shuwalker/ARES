import Foundation

extension DashboardAPIService {

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
