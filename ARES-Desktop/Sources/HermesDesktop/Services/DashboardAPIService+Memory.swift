import Foundation

extension DashboardAPIService {

    // MARK: - Memory

    /// GET /api/memory
    func fetchMemory() async throws -> MemoryResponse {
        let data = try await authenticatedGet(path: "api/memory")
        return try JSONDecoder().decode(MemoryResponse.self, from: data)
    }

    /// DELETE /api/memory/{id}
    func deleteMemoryEntry(id: String) async throws {
        _ = try await authenticatedDelete(path: "api/memory/\(id)")
    }

    /// PUT /api/memory/{id}
    func updateMemoryEntry(id: String, content: String) async throws {
        let body: [String: String] = ["content": content]
        let payload = try JSONSerialization.data(withJSONObject: body)
        _ = try await authenticatedPut(path: "api/memory/\(id)", body: payload)
    }

    // MARK: - Tools

    /// GET /api/tools
    func fetchTools() async throws -> ToolsResponse {
        let data = try await authenticatedGet(path: "api/tools")
        return try JSONDecoder().decode(ToolsResponse.self, from: data)
    }

    /// POST /api/tools/{name}/enable or /api/tools/{name}/disable
    func setToolEnabled(name: String, enabled: Bool) async throws {
        let action = enabled ? "enable" : "disable"
        _ = try await authenticatedPost(path: "api/tools/\(name)/\(action)", body: Data())
    }

    // MARK: - Tool Approvals

    /// GET /api/approvals — returns pending tool approval requests
    func fetchPendingApprovals() async throws -> [ToolApprovalRequest] {
        let data = try await authenticatedGet(path: "api/approvals")
        return try JSONDecoder().decode([ToolApprovalRequest].self, from: data)
    }

    /// POST /api/approvals/{id}/approve — approve a pending tool call
    func approveToolCall(id: String) async throws {
        _ = try await authenticatedPost(path: "api/approvals/\(id)/approve", body: Data())
    }

    /// POST /api/approvals/{id}/deny — deny a pending tool call
    func denyToolCall(id: String) async throws {
        _ = try await authenticatedPost(path: "api/approvals/\(id)/deny", body: Data())
    }
}
