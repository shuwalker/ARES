import Foundation

extension AppState {
    // MARK: - Conductor

    func launchConductorMission() async {
        guard dashboardAPIAvailable, !conductorGoal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        conductorMissionActive = true
        let missionId = UUID().uuidString

        // Determine workers based on goal keywords
        let goal = conductorGoal.lowercased()
        var workers: [(name: String, role: String)] = [("Orchestrator", "Orchestrator")]
        if goal.contains("build") || goal.contains("code") || goal.contains("implement") {
            workers.append(("Builder", "Builder"))
        }
        if goal.contains("review") || goal.contains("check") || goal.contains("audit") {
            workers.append(("Reviewer", "Reviewer"))
        }
        if goal.contains("deploy") || goal.contains("release") || goal.contains("ship") {
            workers.append(("DevOps", "DevOps"))
        }
        if workers.count == 1 {
            workers.append(("Builder", "Builder"))
            workers.append(("Reviewer", "Reviewer"))
        }

        // Create worker cards
        conductorWorkerCards = workers.map { w in
            ConductorWorkerCard(
                id: "\(missionId)-\(w.name)",
                workerName: w.name,
                status: "Idle",
                tokenCount: 0,
                startTime: Date(),
                output: ""
            )
        }

        // Dispatch to each worker
        for (index, worker) in workers.enumerated() {
            let prompt: String
            if worker.name == "Orchestrator" {
                prompt = conductorGoal
            } else {
                prompt = "[\(worker.role) subtask for mission \(missionId)] \(conductorGoal)"
            }
            let cardId = "\(missionId)-\(worker.name)"
            updateConductorCardStatus(id: cardId, status: "Thinking")
            do {
                _ = try await dashboardAPIService.swarmDispatch(
                    worker: worker.name,
                    prompt: prompt,
                    missionId: missionId
                )
                updateConductorCardStatus(id: cardId, status: "Running")
            } catch {
                updateConductorCardStatus(id: cardId, status: "Idle")
            }
            // small stagger between dispatches
            if index < workers.count - 1 {
                try? await Task.sleep(for: .milliseconds(200))
            }
        }

        // Start polling runtime for output
        startConductorPolling(missionId: missionId)
    }

    func stopConductorMission() {
        conductorPollingTask?.cancel()
        conductorPollingTask = nil
        conductorMissionActive = false
        for idx in conductorWorkerCards.indices {
            if conductorWorkerCards[idx].status != "Done" {
                conductorWorkerCards[idx].status = "Idle"
            }
        }
    }

    private func updateConductorCardStatus(id: String, status: String) {
        if let idx = conductorWorkerCards.firstIndex(where: { $0.id == id }) {
            conductorWorkerCards[idx].status = status
        }
    }

    private func startConductorPolling(missionId: String) {
        conductorPollingTask?.cancel()
        conductorPollingTask = Task { [weak self] in
            var pollCount = 0
            while !Task.isCancelled {
                await self?.pollConductorRuntime(missionId: missionId)
                pollCount += 1
                // Stop polling after 5 minutes (150 * 2s)
                if pollCount > 150 {
                    self?.conductorMissionActive = false
                    break
                }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func pollConductorRuntime(missionId _: String) async {
        guard dashboardAPIAvailable else { return }
        do {
            let data = try await dashboardAPIService.fetchSwarmRuntime()
            let runtime = try JSONDecoder().decode(SwarmRuntime.self, from: data)
            guard let workers = runtime.workers, !workers.isEmpty else { return }
            var allDone = true
            for w in workers {
                guard let workerId = w.workerId else { continue }
                if let idx = conductorWorkerCards.firstIndex(where: { $0.workerName == workerId || $0.id.hasSuffix("-\(workerId)") }) {
                    if let output = w.sessionOutput {
                        conductorWorkerCards[idx].output = output
                        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
                        let tokenEstimate = lines.reduce(0) { $0 + $1.count / 4 }
                        conductorWorkerCards[idx].tokenCount = tokenEstimate
                    }
                    if conductorWorkerCards[idx].status != "Done" {
                        allDone = false
                    }
                }
            }
            if allDone && !conductorWorkerCards.isEmpty {
                conductorMissionActive = false
                conductorPollingTask?.cancel()
            }
        } catch {
            // silently ignore polling errors
        }
    }
}
