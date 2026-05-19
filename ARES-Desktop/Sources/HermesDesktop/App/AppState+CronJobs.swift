import Foundation

extension AppState {
    // MARK: - Cron Jobs

    func loadCronJobs() async {
        guard let profile = activeConnection else { return }
        if isLoadingCronJobs { return }

        let previousSelectedCronJobID = selectedCronJobID
        isLoadingCronJobs = true
        cronJobsError = nil

        do {
            let jobs = try await cronBrowserService.listJobs(connection: profile)
            guard isActiveWorkspace(profile) else { return }
            cronJobs = jobs
            isLoadingCronJobs = false

            if let previousSelectedCronJobID,
               jobs.contains(where: { $0.id == previousSelectedCronJobID }) {
                selectedCronJobID = previousSelectedCronJobID
            } else {
                selectedCronJobID = jobs.first?.id
            }
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingCronJobs = false
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load cron jobs"))
        }
    }

    func createCronJob(_ draft: CronJobDraft) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingCronJobDraft, !isOperatingOnCronJob else { return false }

        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            cronJobsError = localizedError
            setStatusMessage(localizedError)
            return false
        }

        isSavingCronJobDraft = true
        cronJobsError = nil
        setStatusMessage(L10n.string("Creating cron job…"))

        do {
            let jobID = try await cronBrowserService.createJob(connection: profile, draft: draft)
            guard isActiveWorkspace(profile) else { return false }
            await loadCronJobs()
            selectedCronJobID = jobID
            isSavingCronJobDraft = false
            setStatusMessage(L10n.string("%@ created", draft.normalizedName))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSavingCronJobDraft = false
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to create cron job"))
            return false
        }
    }

    func updateCronJob(_ job: CronJob, draft: CronJobDraft) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingCronJobDraft, !isOperatingOnCronJob else { return false }

        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            cronJobsError = localizedError
            setStatusMessage(localizedError)
            return false
        }

        isSavingCronJobDraft = true
        cronJobsError = nil
        setStatusMessage(L10n.string("Updating %@…", job.resolvedName))

        do {
            try await cronBrowserService.updateJob(connection: profile, jobID: job.id, draft: draft)
            guard isActiveWorkspace(profile) else { return false }
            await loadCronJobs()
            selectedCronJobID = job.id
            isSavingCronJobDraft = false
            setStatusMessage(L10n.string("%@ updated", draft.normalizedName))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSavingCronJobDraft = false
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to update cron job"))
            return false
        }
    }

    func deleteCronJob(_ job: CronJob) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnCronJob else { return }

        isOperatingOnCronJob = true
        operatingCronJobID = job.id
        cronJobsError = nil

        do {
            try await cronBrowserService.removeJob(connection: profile, jobID: job.id)
            guard isActiveWorkspace(profile) else { return }
            await loadCronJobs()
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            setStatusMessage(L10n.string("%@ removed", job.resolvedName))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to remove cron job"))
        }
    }

    func pauseCronJob(_ job: CronJob) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnCronJob else { return }

        isOperatingOnCronJob = true
        operatingCronJobID = job.id
        cronJobsError = nil

        do {
            try await cronBrowserService.pauseJob(connection: profile, jobID: job.id)
            guard isActiveWorkspace(profile) else { return }
            await loadCronJobs()
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            setStatusMessage(L10n.string("%@ paused", job.resolvedName))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to pause cron job"))
        }
    }

    func resumeCronJob(_ job: CronJob) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnCronJob else { return }

        isOperatingOnCronJob = true
        operatingCronJobID = job.id
        cronJobsError = nil

        do {
            try await cronBrowserService.resumeJob(connection: profile, jobID: job.id)
            guard isActiveWorkspace(profile) else { return }
            await loadCronJobs()
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            setStatusMessage(L10n.string("%@ resumed", job.resolvedName))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to resume cron job"))
        }
    }

    func runCronJobNow(_ job: CronJob) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnCronJob else { return }

        isOperatingOnCronJob = true
        operatingCronJobID = job.id
        cronJobsError = nil
        setStatusMessage(L10n.string("Triggering %@…", job.resolvedName))

        do {
            try await cronBrowserService.runJobNow(connection: profile, jobID: job.id)
            guard isActiveWorkspace(profile) else { return }
            await loadCronJobs()
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            setStatusMessage(L10n.string("Run requested for %@", job.resolvedName))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnCronJob = false
            operatingCronJobID = nil
            cronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to run cron job"))
        }
    }

    // MARK: - Dashboard Cron Jobs (Jobs tab)

    func loadDashboardCronJobs() async {
        guard dashboardAPIAvailable else { return }
        if isLoadingDashboardCronJobs { return }

        isLoadingDashboardCronJobs = true
        dashboardCronJobsError = nil

        do {
            let jobs = try await dashboardAPIService.fetchClaudeJobs()
            dashboardCronJobs = jobs
            isLoadingDashboardCronJobs = false
        } catch {
            isLoadingDashboardCronJobs = false
            dashboardCronJobsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load jobs"))
        }
    }

    func createDashboardCronJob(_ job: DashboardCronJobCreate) async {
        guard dashboardAPIAvailable else { return }

        do {
            _ = try await dashboardAPIService.createClaudeJob(job)
            setStatusMessage(L10n.string("%@ created", job.name))
            await loadDashboardCronJobs()
        } catch {
            dashboardCronJobsError = error.localizedDescription
            setStatusMessage(error.localizedDescription)
        }
    }

    func deleteDashboardCronJob(id: String) async {
        guard dashboardAPIAvailable else { return }

        do {
            try await dashboardAPIService.deleteClaudeJob(id: id)
            dashboardCronJobs.removeAll { $0.id == id }
            setStatusMessage(L10n.string("Job removed"))
        } catch {
            dashboardCronJobsError = error.localizedDescription
            setStatusMessage(error.localizedDescription)
        }
    }

    func toggleDashboardCronJob(id: String, enabled: Bool) async {
        guard dashboardAPIAvailable else { return }

        do {
            let patch = DashboardCronJobPatch(enabled: enabled)
            let updated = try await dashboardAPIService.patchClaudeJob(id: id, patch: patch)
            if let index = dashboardCronJobs.firstIndex(where: { $0.id == id }) {
                dashboardCronJobs[index] = updated
            }
        } catch {
            dashboardCronJobsError = error.localizedDescription
            setStatusMessage(error.localizedDescription)
        }
    }
}
