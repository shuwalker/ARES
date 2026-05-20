import Foundation

extension AppState {
    // MARK: - Swarm

    func loadSwarm() async {
        guard dashboardAPIAvailable else { return }
        guard !isLoadingSwarm else { return }
        isLoadingSwarm = true
        swarmError = nil

        async let rosterResult: [SwarmWorker] = {
            do {
                return try await dashboardAPIService.fetchSwarmRoster()
            } catch {
                await MainActor.run { swarmError = Self.errorMessage(error, feature: "swarm roster") }
                return []
            }
        }()
        async let missionsResult: [SwarmMission] = {
            do {
                return try await dashboardAPIService.fetchSwarmMissions()
            } catch {
                // Missions are secondary — only overwrite error if not already set
                return []
            }
        }()
        async let healthResult: SwarmHealth? = {
            do {
                return try await dashboardAPIService.fetchSwarmHealth()
            } catch {
                return nil
            }
        }()

        let (roster, missions, health) = await (rosterResult, missionsResult, healthResult)
        swarmWorkers = roster
        swarmMissions = missions
        swarmHealth = health
        isLoadingSwarm = false
    }

    func loadSwarmKanban() async {
        guard dashboardAPIAvailable else { return }
        do {
            swarmKanbanCards = try await dashboardAPIService.fetchSwarmKanban()
        } catch {
            swarmError = Self.errorMessage(error, feature: "swarm kanban")
        }
    }

    func loadSwarmReports() async {
        guard dashboardAPIAvailable else { return }
        do {
            swarmReports = try await dashboardAPIService.fetchSwarmReports()
        } catch {
            swarmError = Self.errorMessage(error, feature: "swarm reports")
        }
    }

    func loadSwarmMemory() async {
        guard dashboardAPIAvailable else { return }
        do {
            swarmMemoryFiles = try await dashboardAPIService.fetchSwarmMemory()
        } catch {
            // Memory is non-critical; only log, don't show banner to avoid obscuring primary errors
            swarmError = swarmError ?? Self.errorMessage(error, feature: "swarm memory")
        }
    }

    func dispatchToSwarm(worker: String, prompt: String, missionId: String? = nil) async {
        guard dashboardAPIAvailable else { return }
        do {
            try await dashboardAPIService.swarmDispatch(worker: worker, prompt: prompt, missionId: missionId)
            setStatusMessage(L10n.string("Dispatched to \(worker)"))
            await loadSwarm()
        } catch {
            swarmError = Self.errorMessage(error, feature: "dispatch")
            setStatusMessage(error.localizedDescription)
        }
    }

    /// Sends a direct chat message to the named worker and returns the assistant reply.
    @discardableResult
    func sendSwarmDirectChat(worker: String, message: String) async -> String {
        guard dashboardAPIAvailable else { return "" }
        do {
            let reply = try await dashboardAPIService.swarmDirectChat(worker: worker, message: message)
            setStatusMessage(L10n.string("Message sent to \(worker)"))
            return reply
        } catch {
            swarmError = Self.errorMessage(error, feature: "direct chat")
            return ""
        }
    }

    func moveSwarmKanbanCard(_ card: SwarmKanbanCard, toColumn column: String) async {
        guard dashboardAPIAvailable else { return }
        var updated = card
        updated = SwarmKanbanCard(
            id: card.id,
            title: card.title,
            column: column,
            worker: card.worker,
            priority: card.priority
        )
        if let idx = swarmKanbanCards.firstIndex(where: { $0.id == card.id }) {
            swarmKanbanCards[idx] = updated
        }
        do {
            try await dashboardAPIService.updateSwarmKanbanCard(updated)
        } catch {
            // revert on failure
            await loadSwarmKanban()
        }
    }

    func createSwarmKanbanCard(title: String, worker: String?, priority: String?) async {
        guard dashboardAPIAvailable else { return }
        let draft = SwarmKanbanCard(
            id: UUID().uuidString,
            title: title,
            column: "backlog",
            worker: worker,
            priority: priority
        )
        do {
            let created = try await dashboardAPIService.createSwarmKanbanCard(draft)
            swarmKanbanCards.append(created)
        } catch {
            swarmError = Self.errorMessage(error, feature: "create card")
        }
    }

    func startSwarmPolling() {
        swarmPollingTask?.cancel()
        swarmPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.loadSwarm()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    func stopSwarmPolling() {
        swarmPollingTask?.cancel()
        swarmPollingTask = nil
    }

    func startSwarmRuntimePolling() {
        swarmRuntimePollingTask?.cancel()
        swarmRuntimePollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollSwarmRuntime()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    func stopSwarmRuntimePolling() {
        swarmRuntimePollingTask?.cancel()
        swarmRuntimePollingTask = nil
    }

    private func pollSwarmRuntime() async {
        guard dashboardAPIAvailable else { return }
        do {
            let data = try await dashboardAPIService.fetchSwarmRuntime()
            if let decoded = try? JSONDecoder().decode(SwarmRuntime.self, from: data),
               let workers = decoded.workers {
                var outputMap: [String: String] = [:]
                for w in workers {
                    if let workerId = w.workerId, let output = w.sessionOutput {
                        outputMap[workerId] = output
                    }
                }
                swarmRuntimeOutput = outputMap
            } else if let raw = String(data: data, encoding: .utf8) {
                // fallback: store as single entry
                swarmRuntimeOutput["default"] = raw
            }
        } catch {
            // Polling errors are transient — only surface if not already showing a primary error
        }
    }

    // MARK: - Error message helper

    /// Converts a thrown error into a user-facing string, with special-casing for 404 responses.
    static func errorMessage(_ error: Error, feature: String) -> String {
        let description = error.localizedDescription
        if description.contains("404") || description.contains("Not Found") {
            return "Feature not yet available on this Hermes server (\(feature)). Update Hermes to v2.0+ to enable this feature."
        }
        return description
    }
}
