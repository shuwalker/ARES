import Foundation

extension AppState {
    // MARK: - Operations

    func loadOperations() async {
        guard dashboardAPIAvailable else { return }
        isLoadingOperations = true
        operationsError = nil
        do {
            // Fetch agents from claude-config
            let configData = try await dashboardAPIService.fetchClaudeConfig()
            // Parse agents: try array first, then object with "agents" key
            struct AgentEntry: Decodable {
                let id: String?
                let name: String?
                let role: String?
                let profile: String?
            }
            struct AgentsWrapper: Decodable {
                let agents: [AgentEntry]?
            }
            var agents: [OperationsAgent] = []
            if let wrapper = try? JSONDecoder().decode(AgentsWrapper.self, from: configData),
               let entries = wrapper.agents {
                agents = entries.map { e in
                    OperationsAgent(
                        id: e.id ?? e.name ?? UUID().uuidString,
                        name: e.name ?? e.id ?? "Unknown",
                        role: e.role,
                        profile: e.profile
                    )
                }
            } else if let entries = try? JSONDecoder().decode([AgentEntry].self, from: configData) {
                agents = entries.map { e in
                    OperationsAgent(
                        id: e.id ?? e.name ?? UUID().uuidString,
                        name: e.name ?? e.id ?? "Unknown",
                        role: e.role,
                        profile: e.profile
                    )
                }
            }
            operationsAgents = agents
        } catch {
            operationsError = AppState.errorMessage(error, feature: "operations agents")
        }
        isLoadingOperations = false
    }

    // MARK: - Crew Status

    func loadCrewStatus() async {
        guard dashboardAPIAvailable else { return }
        isLoadingCrewStatus = true
        crewStatusError = nil
        do {
            // Aggregate from profiles and sessions
            let profilesResponse = try await dashboardAPIService.fetchProfiles()
            let jobs = (try? await dashboardAPIService.fetchClaudeJobs()) ?? []

            // Fetch sessions raw to get per-profile stats
            let sessionData = try? await dashboardAPIService.fetchSessionsRaw()

            struct SessionEntry: Decodable {
                let profile: String?
                let tokenCount: Int?
                let messageCount: Int?
                let costUsd: Double?
                enum CodingKeys: String, CodingKey {
                    case profile
                    case tokenCount = "token_count"
                    case messageCount = "message_count"
                    case costUsd = "cost_usd"
                }
            }

            var sessionsByProfile: [String: [SessionEntry]] = [:]
            if let sessionData {
                let sessions = (try? JSONDecoder().decode([SessionEntry].self, from: sessionData)) ?? []
                for session in sessions {
                    let key = session.profile ?? "default"
                    sessionsByProfile[key, default: []].append(session)
                }
            }

            let now = Date()
            var entries: [CrewStatusEntry] = []
            for profile in profilesResponse.profiles {
                let profileSessions = sessionsByProfile[profile.name] ?? []
                let sessionCount = profileSessions.count
                let messageCount = profileSessions.reduce(0) { $0 + ($1.messageCount ?? 0) }
                let tokenCount = profileSessions.reduce(0) { $0 + ($1.tokenCount ?? 0) }
                let estimatedCost = profileSessions.reduce(0.0) { $0 + ($1.costUsd ?? 0.0) }
                let cronCount = jobs.filter { $0.profile == profile.name }.count

                // Consider online if any session within last 5 minutes (heuristic via count > 0)
                let isOnline = sessionCount > 0

                entries.append(CrewStatusEntry(
                    id: profile.name,
                    profileName: profile.name,
                    isOnline: isOnline,
                    sessionCount: sessionCount,
                    messageCount: messageCount,
                    tokenCount: tokenCount,
                    estimatedCost: estimatedCost,
                    cronJobCount: cronCount
                ))
            }

            // If no profiles returned, synthesize from session data
            if entries.isEmpty {
                for (profileName, sessions) in sessionsByProfile {
                    let messageCount = sessions.reduce(0) { $0 + ($1.messageCount ?? 0) }
                    let tokenCount = sessions.reduce(0) { $0 + ($1.tokenCount ?? 0) }
                    let estimatedCost = sessions.reduce(0.0) { $0 + ($1.costUsd ?? 0.0) }
                    let cronCount = jobs.filter { $0.profile == profileName }.count
                    entries.append(CrewStatusEntry(
                        id: profileName,
                        profileName: profileName,
                        isOnline: true,
                        sessionCount: sessions.count,
                        messageCount: messageCount,
                        tokenCount: tokenCount,
                        estimatedCost: estimatedCost,
                        cronJobCount: cronCount
                    ))
                }
            }

            _ = now  // suppress unused warning
            crewStatusEntries = entries.sorted { $0.profileName < $1.profileName }
        } catch {
            crewStatusError = AppState.errorMessage(error, feature: "crew status")
        }
        isLoadingCrewStatus = false
    }

    func startCrewStatusPolling() {
        crewStatusPollingTask?.cancel()
        crewStatusPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { break }
                await self?.loadCrewStatus()
            }
        }
    }

    func stopCrewStatusPolling() {
        crewStatusPollingTask?.cancel()
        crewStatusPollingTask = nil
    }
}
