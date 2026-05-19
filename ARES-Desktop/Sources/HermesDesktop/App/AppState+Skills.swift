import Foundation

extension AppState {
    // MARK: - Skills

    func loadSkills(reset: Bool = false) async {
        guard let profile = activeConnection else { return }
        if isLoadingSkills { return }

        let previousSelectedSkillID = selectedSkillID

        isLoadingSkills = true
        skillsError = nil

        do {
            let items = try await skillBrowserService.listSkills(connection: profile)
            guard isActiveWorkspace(profile) else { return }
            skills = items.sorted { lhs, rhs in
                let comparison = lhs.slug.localizedCaseInsensitiveCompare(rhs.slug)
                if comparison != .orderedSame {
                    return comparison == .orderedAscending
                }

                return lhs.relativePath.localizedCaseInsensitiveCompare(rhs.relativePath) == .orderedAscending
            }
            isLoadingSkills = false

            if reset {
                let preferredSkillID: String?
                if let previousSelectedSkillID,
                   items.contains(where: { $0.id == previousSelectedSkillID }) {
                    preferredSkillID = previousSelectedSkillID
                } else {
                    preferredSkillID = items.first?.id
                }

                if let preferredSkill = items.first(where: { $0.id == preferredSkillID }) {
                    await loadSkillDetail(summary: preferredSkill)
                } else if let firstSkill = items.first {
                    await loadSkillDetail(summary: firstSkill)
                } else {
                    selectedSkillID = nil
                    selectedSkillDetail = nil
                    isLoadingSkillDetail = false
                }
            }
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingSkills = false
            skillsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load skills"))
        }
    }

    func loadSkillDetail(summary: SkillSummary) async {
        guard let profile = activeConnection else { return }
        let skillID = summary.id
        selectedSkillID = skillID
        selectedSkillDetail = nil
        skillsError = nil
        isLoadingSkillDetail = true

        do {
            let detail = try await skillBrowserService.loadSkillDetail(
                connection: profile,
                locator: summary.locator
            )

            guard isActiveWorkspace(profile), selectedSkillID == skillID else { return }
            selectedSkillDetail = detail
            isLoadingSkillDetail = false
        } catch {
            guard isActiveWorkspace(profile), selectedSkillID == skillID else { return }
            selectedSkillDetail = nil
            isLoadingSkillDetail = false
            skillsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load skill detail"))
        }
    }

    func createSkill(_ draft: SkillDraft) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingSkillDraft else { return false }

        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            skillsError = localizedError
            setStatusMessage(localizedError)
            return false
        }

        isSavingSkillDraft = true
        skillsError = nil
        setStatusMessage(L10n.string("Creating skill…"))

        do {
            let detail = try await skillBrowserService.createSkill(
                connection: profile,
                draft: draft
            )
            guard isActiveWorkspace(profile) else { return false }
            await loadSkills(reset: true)
            selectedSkillID = detail.id
            selectedSkillDetail = detail
            isSavingSkillDraft = false
            setStatusMessage(L10n.string("%@ created", draft.normalizedName))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSavingSkillDraft = false
            skillsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to create skill"))
            return false
        }
    }

    func updateSkill(
        _ detail: SkillDetail,
        markdownContent: String,
        ensureReferencesFolder: Bool,
        ensureScriptsFolder: Bool,
        ensureTemplatesFolder: Bool
    ) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingSkillDraft else { return false }

        let normalizedContent = markdownContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedContent.isEmpty else {
            let message = L10n.string("SKILL.md content cannot be empty.")
            skillsError = message
            setStatusMessage(message)
            return false
        }

        isSavingSkillDraft = true
        skillsError = nil
        setStatusMessage(L10n.string("Updating %@…", detail.resolvedName))

        do {
            let updatedDetail = try await skillBrowserService.updateSkill(
                connection: profile,
                locator: detail.locator,
                markdownContent: normalizedContent + "\n",
                expectedContentHash: detail.contentHash,
                ensureReferencesFolder: ensureReferencesFolder,
                ensureScriptsFolder: ensureScriptsFolder,
                ensureTemplatesFolder: ensureTemplatesFolder
            )
            guard isActiveWorkspace(profile) else { return false }
            await loadSkills(reset: true)
            selectedSkillID = updatedDetail.id
            selectedSkillDetail = updatedDetail
            isSavingSkillDraft = false
            setStatusMessage(L10n.string("%@ updated", updatedDetail.resolvedName))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSavingSkillDraft = false
            skillsError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to update skill"))
            return false
        }
    }

    // MARK: - Workflows

    func loadWorkflows(reset: Bool = false) {
        guard let profile = activeConnection else {
            workflows = []
            selectedWorkflowID = nil
            return
        }

        let previousSelectedWorkflowID = selectedWorkflowID
        workflows = connectionStore.workflows(for: profile.workspaceScopeFingerprint)

        guard reset else { return }

        if let previousSelectedWorkflowID,
           workflows.contains(where: { $0.id == previousSelectedWorkflowID }) {
            selectedWorkflowID = previousSelectedWorkflowID
        } else {
            selectedWorkflowID = workflows.first?.id
        }
    }

    func createWorkflow(_ draft: WorkflowDraft) -> Bool {
        guard let profile = activeConnection else { return false }

        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            setStatusMessage(localizedError)
            activeAlert = AppAlert(
                title: L10n.string("Unable to save workflow"),
                message: localizedError
            )
            return false
        }

        let workflow = WorkflowPreset(
            workspaceScopeFingerprint: profile.workspaceScopeFingerprint,
            name: draft.normalizedName,
            prompt: draft.normalizedPrompt,
            assignedSkills: draft.normalizedSelectedSkills
        )

        connectionStore.upsertWorkflow(workflow)
        loadWorkflows(reset: true)
        selectedWorkflowID = workflow.id
        setStatusMessage(L10n.string("%@ created", workflow.name))
        return true
    }

    func updateWorkflow(_ workflow: WorkflowPreset, draft: WorkflowDraft) -> Bool {
        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            setStatusMessage(localizedError)
            activeAlert = AppAlert(
                title: L10n.string("Unable to save workflow"),
                message: localizedError
            )
            return false
        }

        let updatedWorkflow = workflow.updated(
            name: draft.normalizedName,
            prompt: draft.normalizedPrompt,
            assignedSkills: draft.normalizedSelectedSkills
        )

        connectionStore.upsertWorkflow(updatedWorkflow)
        loadWorkflows(reset: true)
        selectedWorkflowID = updatedWorkflow.id
        setStatusMessage(L10n.string("%@ updated", updatedWorkflow.name))
        return true
    }

    func deleteWorkflow(_ workflow: WorkflowPreset) {
        connectionStore.removeWorkflow(id: workflow.id)
        loadWorkflows(reset: true)
        setStatusMessage(L10n.string("%@ removed", workflow.name))
    }

    func workflow(id: UUID?) -> WorkflowPreset? {
        guard let id else { return nil }
        return workflows.first(where: { $0.id == id })
    }

    func runWorkflow(_ workflow: WorkflowPreset) async {
        guard let profile = activeConnection else {
            activeAlert = AppAlert(
                title: L10n.string("No active connection"),
                message: L10n.string("Select a connection before running a workflow.")
            )
            setStatusMessage(L10n.string("No active connection"))
            return
        }

        if skills.isEmpty && !isLoadingSkills {
            await loadSkills(reset: false)
        }

        let skillsByRelativePath = Dictionary(uniqueKeysWithValues: skills.map { ($0.relativePath, $0) })
        let missingSkills = workflow.assignedSkills.filter { skillsByRelativePath[$0.relativePath] == nil }

        guard missingSkills.isEmpty else {
            let message: String
            if let skillsError,
               skills.isEmpty {
                message = skillsError
            } else {
                message = L10n.string(
                    "This workflow references skills that are not available on the active host/profile: %@",
                    missingSkills.map(\.relativePath).joined(separator: ", ")
                )
            }

            activeAlert = AppAlert(
                title: L10n.string("Workflow cannot run"),
                message: message
            )
            setStatusMessage(L10n.string("Workflow cannot run"))
            return
        }

        let invocation = WorkflowLaunchInvocation(workflow: workflow, connection: profile)
        let workflowLaunchDiagnosticsContext = WorkflowLaunchDiagnosticsContext(
            workflow: workflow,
            invocation: invocation,
            connection: profile
        )
        await workflowLaunchDiagnostics.recordWorkflowRunRequested(workflowLaunchDiagnosticsContext)
        terminalWorkspace.addCommandTab(
            for: profile.updated(),
            commandLine: invocation.startupCommandLine,
            initialInput: invocation.initialInput,
            workflowLaunchDiagnosticsContext: workflowLaunchDiagnosticsContext
        )
        selectedSection = .terminal
        handleSectionEntry(.terminal)
        setStatusMessage(L10n.string("Opening %@ in Terminal…", workflow.name))
    }

    func refreshWorkflows() async {
        loadWorkflows(reset: true)
        await loadSkills(reset: false)
        loadWorkflows(reset: true)
    }

    func refreshSkills() async {
        guard !isLoadingSkills, !isRefreshingSkills else { return }
        isRefreshingSkills = true
        await loadSkills(reset: true)
        isRefreshingSkills = false
    }
}
