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
}
