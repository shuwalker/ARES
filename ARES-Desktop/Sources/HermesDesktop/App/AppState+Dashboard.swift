import Foundation

extension AppState {
    // MARK: - Dashboard Analytics (Feature 1)

    func loadDashboardOverview() async {
        guard dashboardAPIAvailable else { return }
        isLoadingDashboard = true
        do {
            let overview = try await dashboardAPIService.fetchDashboardOverview(period: dashboardPeriod)
            dashboardOverview = overview
        } catch {
            // silently ignore — view shows ContentUnavailableView when data is nil
        }
        isLoadingDashboard = false
    }

    // MARK: - Usage Meter / Session Context (Feature 2)

    func startContextPolling() {
        guard dashboardAPIAvailable else { return }
        contextPollingTask?.cancel()
        firedContextThresholds = []
        contextPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollSessionContext()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    func stopContextPolling() {
        contextPollingTask?.cancel()
        contextPollingTask = nil
    }

    func pollSessionContext() async {
        guard dashboardAPIAvailable else { return }
        do {
            let status = try await dashboardAPIService.fetchSessionStatus()
            sessionContextUsed = status.contextUsed
            sessionContextLimit = max(status.contextLimit, 1)
            sessionDailyCost = status.dailyCost

            let pct = Int(Double(sessionContextUsed) / Double(sessionContextLimit) * 100)
            for threshold in [50, 75, 90] {
                if pct >= threshold && !firedContextThresholds.contains(threshold) {
                    firedContextThresholds.insert(threshold)
                    contextAlertThreshold = threshold
                    break
                }
            }
        } catch {
            // silently ignore polling errors
        }
    }

    func dismissContextAlert() {
        contextAlertThreshold = nil
    }
}
