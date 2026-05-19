import Foundation

extension DashboardAPIService {

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
    func swarmDispatch(worker: String, prompt: String, missionId: String? = nil) async throws {
        let request = SwarmDispatchRequest(worker: worker, prompt: prompt, missionId: missionId)
        let payload = try JSONEncoder().encode(request)
        _ = try await authenticatedPost(path: "api/swarm-dispatch", body: payload)
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

    /// POST /api/swarm-chat — chat with entire swarm
    func swarmChat(message: String) async throws {
        let body: [String: String] = ["message": message]
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await authenticatedPost(path: "api/swarm-chat", body: payload)
    }

    /// POST /api/swarm-direct-chat — chat with a specific worker
    func swarmDirectChat(worker: String, message: String) async throws {
        let request = SwarmDirectChatRequest(worker: worker, message: message)
        let payload = try JSONEncoder().encode(request)
        _ = try await authenticatedPost(path: "api/swarm-direct-chat", body: payload)
    }
}
