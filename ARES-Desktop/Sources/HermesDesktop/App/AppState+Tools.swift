import Foundation

extension AppState {
    // MARK: - Tools

    func loadTools() async {
        isLoadingTools = true
        toolsError = nil
        do {
            let response = try await dashboardAPIService.fetchTools()
            tools = response.tools
            isLoadingTools = false
        } catch {
            isLoadingTools = false
            toolsError = error.localizedDescription
        }
    }

    func setToolEnabled(name: String, enabled: Bool) async {
        do {
            try await dashboardAPIService.setToolEnabled(name: name, enabled: enabled)
            if let idx = tools.firstIndex(where: { $0.name == name }) {
                tools[idx].enabled = enabled
            }
        } catch {
            toolsError = error.localizedDescription
        }
    }

    // MARK: - Tool Approvals

    func startApprovalPolling() {
        approvalPollingTask?.cancel()
        approvalPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                if let self, self.dashboardAPIAvailable {
                    await self.pollApprovals()
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopApprovalPolling() {
        approvalPollingTask?.cancel()
        approvalPollingTask = nil
        pendingApprovals = []
    }

    func pollApprovals() async {
        guard dashboardAPIAvailable else { return }
        do {
            let approvals = try await dashboardAPIService.fetchPendingApprovals()
            pendingApprovals = approvals
        } catch {
            // Silently ignore polling errors — the approval UI will just stay hidden
        }
    }

    func approveToolCall(_ approval: ToolApprovalRequest) async {
        do {
            try await dashboardAPIService.approveToolCall(id: approval.id)
            pendingApprovals.removeAll { $0.id == approval.id }
        } catch {
            // Re-poll to get fresh state on failure
            await pollApprovals()
        }
    }

    func denyToolCall(_ approval: ToolApprovalRequest) async {
        do {
            try await dashboardAPIService.denyToolCall(id: approval.id)
            pendingApprovals.removeAll { $0.id == approval.id }
        } catch {
            // Re-poll to get fresh state on failure
            await pollApprovals()
        }
    }
}
