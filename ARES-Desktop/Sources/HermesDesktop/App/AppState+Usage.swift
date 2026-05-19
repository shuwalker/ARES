import Foundation

extension AppState {
    // MARK: - Usage

    func loadUsage(forceRefresh: Bool = false) async {
        guard let profile = activeConnection else { return }
        if isLoadingUsage { return }
        if !forceRefresh {
            if usageSummary != nil || usageError != nil {
                return
            }
        }

        isLoadingUsage = true
        usageError = nil

        do {
            let summary = try await usageBrowserService.loadUsage(
                connection: profile,
                hintedSessionStore: overview?.sessionStore
            )
            guard isActiveWorkspace(profile) else { return }

            let profileBreakdown: UsageProfileBreakdown?
            if let overview,
               overview.availableProfiles.count > 1 {
                profileBreakdown = await loadUsageProfileBreakdown(
                    using: profile,
                    activeSummary: summary,
                    discoveredProfiles: overview.availableProfiles
                )
            } else {
                profileBreakdown = nil
            }
            guard isActiveWorkspace(profile) else { return }

            usageSummary = summary
            usageProfileBreakdown = profileBreakdown
            isLoadingUsage = false
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingUsage = false
            usageSummary = nil
            usageProfileBreakdown = nil
            usageError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load usage"))
        }
    }

    func refreshUsage() async {
        guard !isLoadingUsage, !isRefreshingUsage else { return }
        isRefreshingUsage = true
        await loadUsage(forceRefresh: true)
        isRefreshingUsage = false
    }

    func loadAnalytics(forceRefresh: Bool = false) async {
        guard let profile = activeConnection else { return }
        if isLoadingAnalytics { return }
        guard forceRefresh || analyticsResponse == nil else { return }

        isLoadingAnalytics = true
        analyticsError = nil

        do {
            let response = try await dashboardAPIService.fetchAnalyticsUsage(days: analyticsDays)
            guard isActiveWorkspace(profile) else { return }
            analyticsResponse = response
            isLoadingAnalytics = false
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingAnalytics = false
            analyticsResponse = nil
            analyticsError = error.localizedDescription
        }
    }

    func loadModelsAnalytics(forceRefresh: Bool = false) async {
        guard let profile = activeConnection else { return }
        if isLoadingAnalytics { return }
        guard forceRefresh || modelsAnalyticsResponse == nil else { return }

        isLoadingAnalytics = true
        analyticsError = nil

        do {
            let response = try await dashboardAPIService.fetchModelsAnalytics(days: analyticsDays)
            guard isActiveWorkspace(profile) else { return }
            modelsAnalyticsResponse = response
            isLoadingAnalytics = false
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingAnalytics = false
            modelsAnalyticsResponse = nil
            analyticsError = error.localizedDescription
        }
    }

    func refreshAnalytics() async {
        guard !isLoadingAnalytics, !isRefreshingAnalytics else { return }
        isRefreshingAnalytics = true
        await loadAnalytics(forceRefresh: true)
        await loadModelsAnalytics(forceRefresh: true)
        isRefreshingAnalytics = false
    }

    func loadUsageProfileBreakdown(
        using connection: ConnectionProfile,
        activeSummary: UsageSummary,
        discoveredProfiles: [RemoteHermesProfile]
    ) async -> UsageProfileBreakdown {
        var slices: [UsageProfileSlice] = []
        let activeProfileName = connection.resolvedHermesProfileName

        for discoveredProfile in discoveredProfiles {
            if discoveredProfile.name == activeProfileName {
                slices.append(
                    usageProfileSlice(
                        for: discoveredProfile,
                        summary: activeSummary,
                        activeProfileName: activeProfileName
                    )
                )
                continue
            }

            let scopedConnection = connection.applyingHermesProfile(named: discoveredProfile.name)

            do {
                let summary = try await usageBrowserService.loadUsage(
                    connection: scopedConnection,
                    hintedSessionStore: nil
                )

                slices.append(
                    usageProfileSlice(
                        for: discoveredProfile,
                        summary: summary,
                        activeProfileName: activeProfileName
                    )
                )
            } catch {
                slices.append(
                    UsageProfileSlice(
                        profileName: discoveredProfile.name,
                        hermesHomePath: discoveredProfile.path,
                        state: .unavailable,
                        sessionCount: 0,
                        inputTokens: 0,
                        outputTokens: 0,
                        cacheReadTokens: 0,
                        cacheWriteTokens: 0,
                        reasoningTokens: 0,
                        databasePath: nil,
                        message: error.localizedDescription,
                        isActiveProfile: discoveredProfile.name == activeProfileName
                    )
                )
            }
        }

        return UsageProfileBreakdown(profiles: slices)
    }

    private func usageProfileSlice(
        for discoveredProfile: RemoteHermesProfile,
        summary: UsageSummary,
        activeProfileName: String
    ) -> UsageProfileSlice {
        UsageProfileSlice(
            profileName: discoveredProfile.name,
            hermesHomePath: discoveredProfile.path,
            state: summary.state,
            sessionCount: summary.sessionCount,
            inputTokens: summary.inputTokens,
            outputTokens: summary.outputTokens,
            cacheReadTokens: summary.cacheReadTokens,
            cacheWriteTokens: summary.cacheWriteTokens,
            reasoningTokens: summary.reasoningTokens,
            databasePath: summary.databasePath,
            message: summary.message,
            isActiveProfile: discoveredProfile.name == activeProfileName
        )
    }
}
