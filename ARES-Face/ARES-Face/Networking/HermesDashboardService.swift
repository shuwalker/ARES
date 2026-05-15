import Foundation

/// REST client for Hermes Dashboard API running on localhost:9119.
///
/// Provides sessions, skills, cron, config, and logs — the actual Hermes
/// management data. Auth token is fetched from the running dashboard HTML
/// on first use, or provided directly.
///
/// All calls are async throws. Errors include the HTTP status and response body.
@MainActor
final class HermesDashboardService {
    static let shared = HermesDashboardService()
    
    private let baseURL = "http://localhost:9119"
    private var authToken: String?
    private var tokenFetchAttempted = false
    
    // MARK: - Auth
    
    private func ensureToken() async throws -> String {
        if let token = authToken { return token }
        guard !tokenFetchAttempted else {
            throw DashboardError.notAuthenticated
        }
        tokenFetchAttempted = true
        // Fetch the dashboard HTML and extract the session token
        let (data, _) = try await URLSession.shared.data(from: URL(string: baseURL)!)
        guard let html = String(data: data, encoding: .utf8),
              let tokenRange = html.range(of: "__HERMES_SESSION_TOKEN__=\""),
              let endRange = html[tokenRange.upperBound...].range(of: "\"") else {
            throw DashboardError.tokenNotFound
        }
        let token = String(html[tokenRange.upperBound..<endRange.lowerBound])
        authToken = token
        return token
    }
    
    // MARK: - API Calls
    
    func listSessions(offset: Int = 0, limit: Int = 50, query: String = "") async throws -> [Session] {
        var path = "/api/sessions?offset=\(offset)&limit=\(limit)"
        if !query.isEmpty { path += "&query=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)" }
        let data = try await authenticatedGet(path)
        let dict = try JSONDecoder().decode(SessionListResponse.self, from: data)
        return dict.sessions
    }
    
    func listSkills() async throws -> [Skill] {
        let data = try await authenticatedGet("/api/skills")
        return try JSONDecoder().decode([Skill].self, from: data)
    }
    
    func listCronJobs() async throws -> [CronJob] {
        let data = try await authenticatedGet("/api/cron")
        let dict = try JSONDecoder().decode(CronListResponse.self, from: data)
        return dict.jobs
    }
    
    func pauseCronJob(_ jobID: String) async throws {
        let body: [String: String] = ["action": "pause", "job_id": jobID]
        _ = try await authenticatedPost("/api/cron/action", body: body)
    }
    
    func resumeCronJob(_ jobID: String) async throws {
        let body: [String: String] = ["action": "resume", "job_id": jobID]
        _ = try await authenticatedPost("/api/cron/action", body: body)
    }
    
    func deleteCronJob(_ jobID: String) async throws {
        let body: [String: String] = ["action": "remove", "job_id": jobID]
        _ = try await authenticatedPost("/api/cron/action", body: body)
    }
    
    func runCronJob(_ jobID: String) async throws {
        let body: [String: String] = ["action": "run", "job_id": jobID]
        _ = try await authenticatedPost("/api/cron/action", body: body)
    }
    
    func getConfig() async throws -> Config {
        let data = try await authenticatedGet("/api/config")
        return try JSONDecoder().decode(Config.self, from: data)
    }
    
    func getLogs(lines: Int = 100, level: String = "") async throws -> [String] {
        var path = "/api/logs?lines=\(lines)"
        if !level.isEmpty { path += "&level=\(level)" }
        let data = try await authenticatedGet(path)
        let dict = try JSONDecoder().decode(LogsResponse.self, from: data)
        return dict.lines
    }
    
    func getSessionDetail(_ sessionID: String) async throws -> SessionDetail {
        let path = "/api/sessions/\(sessionID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sessionID)"
        let data = try await authenticatedGet(path)
        return try JSONDecoder().decode(SessionDetail.self, from: data)
    }
    
    // MARK: - HTTP
    
    private func authenticatedGet(_ path: String) async throws -> Data {
        let token = try await ensureToken()
        guard let url = URL(string: "\(baseURL)\(path)") else { throw DashboardError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw DashboardError.unknown }
        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw DashboardError.httpError(httpResponse.statusCode, body)
        }
        return data
    }
    
    private func authenticatedPost(_ path: String, body: [String: Any]) async throws -> Data {
        let token = try await ensureToken()
        guard let url = URL(string: "\(baseURL)\(path)") else { throw DashboardError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw DashboardError.unknown }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            throw DashboardError.httpError(httpResponse.statusCode, body)
        }
        return data
    }
    
    func resetAuth() {
        authToken = nil
        tokenFetchAttempted = false
    }
}

// MARK: - Models

struct SessionListResponse: Codable {
    let sessions: [Session]
    let total: Int?
}

struct Session: Codable, Identifiable, Hashable {
    let id: String
    let source: String?
    let model: String?
    let startedAt: Double?
    let lastActive: Double?
    let messageCount: Int?
    let preview: String?
    let isActive: Bool?
    
    enum CodingKeys: String, CodingKey {
        case id, source, model, preview
        case startedAt = "started_at"
        case lastActive = "last_active"
        case messageCount = "message_count"
        case isActive = "is_active"
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    static func == (lhs: Session, rhs: Session) -> Bool { lhs.id == rhs.id }
}

struct SessionDetail: Codable {
    let session: Session?
    let messages: [SessionMessage]?
}

struct SessionMessage: Codable, Identifiable {
    let id: String
    let role: String
    let content: String
    let timestamp: Double?
}

struct Skill: Codable, Identifiable, Hashable {
    var id: String { name }
    let name: String
    let description: String
    let category: String
    let enabled: Bool
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
    static func == (lhs: Skill, rhs: Skill) -> Bool { lhs.name == rhs.name }
}

struct CronListResponse: Codable {
    let jobs: [CronJob]
}

struct CronJob: Codable, Identifiable {
    let id: String
    let name: String?
    let prompt: String?
    let schedule: String?
    let state: String?
    let enabled: Bool?
    let createdAt: Double?
    let nextRunAt: Double?
    let lastRunAt: Double?
    let lastStatus: String?
    let lastError: String?
    let model: String?
    let provider: String?
    let deliveryTarget: String?
    
    enum CodingKeys: String, CodingKey {
        case id, name, prompt, schedule, state, enabled, model, provider
        case createdAt = "created_at"
        case nextRunAt = "next_run_at"
        case lastRunAt = "last_run_at"
        case lastStatus = "last_status"
        case lastError = "last_error"
        case deliveryTarget = "delivery_target"
    }
}

struct Config: Codable {
    let model: String?
    let agent: AgentConfig?
    let terminal: TerminalConfig?
    let toolsets: [String]?
    let gateway: GatewayConfig?
}

struct AgentConfig: Codable {
    let maxTurns: Int?
    let reasoningEffort: String?
    let verbose: Bool?
    let personalities: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case maxTurns = "max_turns"
        case reasoningEffort = "reasoning_effort"
        case verbose, personalities
    }
}

struct TerminalConfig: Codable {
    let backend: String?
    let timeout: Int?
    let cwd: String?
    let persistentShell: Bool?
    
    enum CodingKeys: String, CodingKey {
        case backend, timeout, cwd
        case persistentShell = "persistent_shell"
    }
}

struct GatewayConfig: Codable {
    let timeout: Int?
    let notifyInterval: Int?
    
    enum CodingKeys: String, CodingKey {
        case timeout = "gateway_timeout"
        case notifyInterval = "gateway_notify_interval"
    }
}

struct LogsResponse: Codable {
    let file: String?
    let lines: [String]
}

enum DashboardError: Error, LocalizedError {
    case notAuthenticated
    case tokenNotFound
    case invalidURL
    case httpError(Int, String)
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not authenticated to Hermes dashboard"
        case .tokenNotFound: return "Could not find auth token in dashboard HTML"
        case .invalidURL: return "Invalid URL"
        case .httpError(let code, let body): return "HTTP \(code): \(body.prefix(200))"
        case .unknown: return "Unknown dashboard error"
        }
    }
}