import Foundation

extension DashboardAPIService {

    // MARK: - Kanban

    /// PATCH /api/plugins/kanban/tasks/{taskID} — move task to a new status column
    func kanbanMoveTask(boardSlug: String, taskID: String, statusRawValue: String) async throws {
        let body: [String: String] = ["status": statusRawValue, "board": boardSlug]
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await authenticatedPost(path: "api/plugins/kanban/tasks/\(taskID)", body: payload)
    }

    /// POST /api/plugins/kanban/tasks/{task_id}/decompose
    /// LLM decomposes the task into subtasks on the given board.
    func kanbanDecomposeTask(taskID: String, boardSlug: String) async throws {
        let body: [String: String] = ["board": boardSlug]
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await authenticatedPost(path: "api/plugins/kanban/tasks/\(taskID)/decompose", body: payload)
    }

    /// GET /api/plugins/kanban/tasks/{task_id}/log?board={boardSlug}
    /// Returns the worker stdout/stderr log text for the given task.
    func kanbanGetTaskLog(taskID: String, boardSlug: String) async throws -> String {
        let path = "api/plugins/kanban/tasks/\(taskID)/log?board=\(boardSlug)"
        let data = try await authenticatedGet(path: path)
        struct LogResponse: Decodable {
            let log: String?
            let text: String?
        }
        if let response = try? JSONDecoder().decode(LogResponse.self, from: data) {
            return response.log ?? response.text ?? ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// GET /api/plugins/kanban/orchestration
    /// Returns the current orchestration configuration.
    func kanbanGetOrchestration() async throws -> KanbanOrchestrationConfig {
        let data = try await authenticatedGet(path: "api/plugins/kanban/orchestration")
        return try JSONDecoder().decode(KanbanOrchestrationConfig.self, from: data)
    }

    /// PUT /api/plugins/kanban/orchestration
    /// Updates the orchestration configuration.
    func kanbanUpdateOrchestration(_ config: KanbanOrchestrationConfig) async throws {
        let payload = try JSONEncoder().encode(config)
        _ = try await authenticatedPut(path: "api/plugins/kanban/orchestration", body: payload)
    }

    /// POST /api/plugins/kanban/tasks/bulk
    /// Bulk-patches a list of tasks (e.g. status change).
    func kanbanBulkUpdateTasks(taskIDs: [String], status: KanbanTaskStatus, boardSlug: String) async throws {
        let body: [String: Any] = [
            "board": boardSlug,
            "task_ids": taskIDs,
            "patch": ["status": status.rawValue]
        ]
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await authenticatedPost(path: "api/plugins/kanban/tasks/bulk", body: payload)
    }

    /// PATCH /api/plugins/kanban/profiles/{profile_name}
    /// Updates a profile's description field.
    func kanbanUpdateProfileDescription(profileName: String, description: String) async throws {
        try await ensureSessionToken()
        let path = "api/plugins/kanban/profiles/\(profileName)"
        let body: [String: String] = ["description": description]
        let payload = try JSONSerialization.data(withJSONObject: body)

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
    }

    /// POST /api/plugins/kanban/profiles/{profile_name}/describe-auto
    /// LLM auto-generates a profile description and returns it.
    func kanbanAutoDescribeProfile(profileName: String) async throws -> String {
        let data = try await authenticatedPost(
            path: "api/plugins/kanban/profiles/\(profileName)/describe-auto",
            body: Data()
        )
        struct DescribeResponse: Decodable {
            let description: String?
            let text: String?
        }
        if let response = try? JSONDecoder().decode(DescribeResponse.self, from: data) {
            return response.description ?? response.text ?? ""
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
