import Foundation

extension AppState {
    // MARK: - Kanban

    func loadKanbanBoards() async {
        guard let profile = activeConnection else { return }
        if isLoadingKanbanBoards { return }

        isLoadingKanbanBoards = true
        kanbanError = nil

        do {
            let response = try await kanbanBrowserService.loadBoards(connection: profile)
            guard isActiveWorkspace(profile) else { return }

            let activeBoards = response.boards.filter { !$0.archived }
            kanbanBoards = activeBoards.isEmpty
                ? [KanbanProject(slug: KanbanProject.defaultSlug)]
                : activeBoards
            remoteCurrentKanbanBoardSlug = response.current
            supportsKanbanBoardManagement = response.supportsBoardManagement

            if !kanbanBoards.contains(where: { $0.slug == selectedKanbanBoardSlug }) {
                if let current = response.current,
                   kanbanBoards.contains(where: { $0.slug == current }) {
                    selectedKanbanBoardSlug = current
                } else {
                    selectedKanbanBoardSlug = kanbanBoards.first?.slug ?? KanbanProject.defaultSlug
                }
            }

            isLoadingKanbanBoards = false
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingKanbanBoards = false
            kanbanBoards = kanbanBoards.isEmpty ? [KanbanProject(slug: KanbanProject.defaultSlug)] : kanbanBoards
            remoteCurrentKanbanBoardSlug = nil
            supportsKanbanBoardManagement = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load Kanban boards"))
        }
    }

    func selectKanbanBoard(_ slug: String) async {
        let normalizedSlug = slug.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedSlug.isEmpty else { return }
        guard selectedKanbanBoardSlug != normalizedSlug else { return }
        guard kanbanBoards.isEmpty || kanbanBoards.contains(where: { $0.slug == normalizedSlug }) else { return }

        selectedKanbanBoardSlug = normalizedSlug
        selectedKanbanTaskID = nil
        selectedKanbanTaskDetail = nil
        kanbanBoard = nil
        await loadKanbanBoard()
    }

    func loadKanbanBoard(includeArchived: Bool? = nil) async {
        guard let profile = activeConnection else { return }
        if isLoadingKanbanBoard { return }

        if let includeArchived {
            includeArchivedKanbanTasks = includeArchived
        }

        if kanbanBoards.isEmpty, !isLoadingKanbanBoards {
            await loadKanbanBoards()
        }

        let boardSlug = selectedKanbanBoardSlug
        let previousSelectedTaskID = selectedKanbanTaskID
        isLoadingKanbanBoard = true
        kanbanError = nil

        do {
            let board = try await kanbanBrowserService.loadBoard(
                connection: profile,
                boardSlug: boardSlug,
                includeArchived: includeArchivedKanbanTasks
            )
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return }
            kanbanBoard = board
            isLoadingKanbanBoard = false

            let nextSelectedTaskID: String?
            if let previousSelectedTaskID,
               board.tasks.contains(where: { $0.id == previousSelectedTaskID }) {
                nextSelectedTaskID = previousSelectedTaskID
            } else {
                nextSelectedTaskID = board.tasks.first?.id
            }

            selectedKanbanTaskID = nextSelectedTaskID
            if let nextSelectedTaskID {
                await loadKanbanTaskDetail(taskID: nextSelectedTaskID)
            } else {
                selectedKanbanTaskDetail = nil
            }
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isLoadingKanbanBoard = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load Kanban board"))
        }
    }

    func loadKanbanTaskDetail(taskID: String) async {
        guard let profile = activeConnection else { return }
        let boardSlug = selectedKanbanBoardSlug

        selectedKanbanTaskID = taskID
        isLoadingKanbanTaskDetail = true
        kanbanError = nil

        do {
            let detail = try await kanbanBrowserService.loadTaskDetail(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID
            )
            guard isActiveWorkspace(profile),
                  selectedKanbanBoardSlug == boardSlug,
                  selectedKanbanTaskID == taskID else { return }
            selectedKanbanTaskDetail = detail
            isLoadingKanbanTaskDetail = false
        } catch {
            guard isActiveWorkspace(profile),
                  selectedKanbanBoardSlug == boardSlug,
                  selectedKanbanTaskID == taskID else { return }
            selectedKanbanTaskDetail = nil
            isLoadingKanbanTaskDetail = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to load Kanban task"))
        }
    }

    func createKanbanBoard(_ draft: KanbanBoardDraft) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingKanbanBoardDraft, !isOperatingOnKanbanBoard else { return false }

        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            kanbanError = localizedError
            setStatusMessage(localizedError)
            return false
        }

        isSavingKanbanBoardDraft = true
        kanbanError = nil
        setStatusMessage(L10n.string("Creating Kanban board..."))

        do {
            let board = try await kanbanBrowserService.createBoard(connection: profile, draft: draft)
            guard isActiveWorkspace(profile) else { return false }
            await loadKanbanBoards()
            selectedKanbanBoardSlug = board.slug
            selectedKanbanTaskID = nil
            selectedKanbanTaskDetail = nil
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            isSavingKanbanBoardDraft = false
            setStatusMessage(L10n.string("%@ created", board.resolvedName))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSavingKanbanBoardDraft = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to create Kanban board"))
            return false
        }
    }

    func archiveKanbanBoard(_ board: KanbanProject) async {
        guard let profile = activeConnection else { return }
        guard !board.isDefault, !isOperatingOnKanbanBoard else { return }

        isOperatingOnKanbanBoard = true
        kanbanError = nil
        setStatusMessage(L10n.string("Archiving %@...", board.resolvedName))

        do {
            try await kanbanBrowserService.archiveBoard(connection: profile, slug: board.slug)
            guard isActiveWorkspace(profile) else { return }
            if selectedKanbanBoardSlug == board.slug {
                selectedKanbanBoardSlug = KanbanProject.defaultSlug
                selectedKanbanTaskID = nil
                selectedKanbanTaskDetail = nil
                kanbanBoard = nil
            }
            await loadKanbanBoards()
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            isOperatingOnKanbanBoard = false
            setStatusMessage(L10n.string("%@ archived", board.resolvedName))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnKanbanBoard = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to archive Kanban board"))
        }
    }

    func createKanbanTask(_ draft: KanbanTaskDraft) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isSavingKanbanTaskDraft, !isOperatingOnKanbanTask else { return false }

        if let validationError = draft.validationError {
            let localizedError = L10n.string(validationError)
            kanbanError = localizedError
            setStatusMessage(localizedError)
            return false
        }

        isSavingKanbanTaskDraft = true
        kanbanError = nil
        setStatusMessage(L10n.string("Creating Kanban task..."))

        do {
            let boardSlug = selectedKanbanBoardSlug
            let taskID = try await kanbanBrowserService.createTask(connection: profile, boardSlug: boardSlug, draft: draft)
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return false }
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            selectedKanbanTaskID = taskID
            await loadKanbanTaskDetail(taskID: taskID)
            isSavingKanbanTaskDraft = false
            setStatusMessage(L10n.string("Kanban task created"))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isSavingKanbanTaskDraft = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to create Kanban task"))
            return false
        }
    }

    func addKanbanComment(taskID: String, body: String) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isOperatingOnKanbanTask else { return false }

        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskID
        kanbanError = nil

        do {
            let boardSlug = selectedKanbanBoardSlug
            try await kanbanBrowserService.addComment(connection: profile, boardSlug: boardSlug, taskID: taskID, body: trimmed)
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return false }
            await reloadKanbanAfterOperation(taskID: taskID, boardSlug: boardSlug)
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            setStatusMessage(L10n.string("Comment added"))
            return true
        } catch {
            guard isActiveWorkspace(profile) else { return false }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to add Kanban comment"))
            return false
        }
    }

    func updateKanbanTaskFields(
        taskID: String,
        body: String,
        tenant: String,
        priority: Int,
        skills: [String]
    ) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task details updated",
            failureMessage: "Unable to update Kanban task details"
        ) { profile, boardSlug in
            try await kanbanBrowserService.updateTaskFields(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                body: body,
                tenant: tenant,
                priority: priority,
                skills: skills
            )
        }
    }

    func setKanbanTaskParents(taskID: String, parentIDs: [String]) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task parents updated",
            failureMessage: "Unable to update Kanban task parents"
        ) { profile, boardSlug in
            try await kanbanBrowserService.setTaskParents(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                parentIDs: parentIDs
            )
        }
    }

    func setKanbanTaskChildren(taskID: String, childIDs: [String]) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task children updated",
            failureMessage: "Unable to update Kanban task children"
        ) { profile, boardSlug in
            try await kanbanBrowserService.setTaskChildren(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                childIDs: childIDs
            )
        }
    }

    func assignKanbanTask(taskID: String, assignee: String?) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task assigned",
            failureMessage: "Unable to assign Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.assignTask(connection: profile, boardSlug: boardSlug, taskID: taskID, assignee: assignee)
        }
    }

    func specifyKanbanTask(taskID: String) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task specified",
            failureMessage: "Unable to specify Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.specifyTask(connection: profile, boardSlug: boardSlug, taskID: taskID)
        }
    }

    func blockKanbanTask(taskID: String, reason: String?) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task blocked",
            failureMessage: "Unable to block Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.blockTask(connection: profile, boardSlug: boardSlug, taskID: taskID, reason: reason)
        }
    }

    func unblockKanbanTask(taskID: String) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task unblocked",
            failureMessage: "Unable to unblock Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.unblockTask(connection: profile, boardSlug: boardSlug, taskID: taskID)
        }
    }

    func completeKanbanTask(taskID: String, result: String?) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task completed",
            failureMessage: "Unable to complete Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.completeTask(connection: profile, boardSlug: boardSlug, taskID: taskID, result: result)
        }
    }

    func moveKanbanTask(taskID: String, toStatus newStatus: KanbanTaskStatus) async {
        guard dashboardAPIAvailable else { return }
        let boardSlug = selectedKanbanBoardSlug

        // Optimistic update
        var revertTasks: [KanbanTask]?
        if var board = kanbanBoard {
            revertTasks = board.tasks
            if let idx = board.tasks.firstIndex(where: { $0.id == taskID }) {
                var updated = board.tasks[idx]
                updated = KanbanTask(
                    id: updated.id,
                    title: updated.title,
                    body: updated.body,
                    status: newStatus,
                    priority: updated.priority,
                    assignee: updated.assignee,
                    tenant: updated.tenant,
                    skills: updated.skills,
                    parentIDs: updated.parentIDs,
                    childIDs: updated.childIDs,
                    createdAt: updated.createdAt,
                    updatedAt: updated.updatedAt
                )
                board.tasks[idx] = updated
                kanbanBoard = board
            }
        }

        do {
            try await dashboardAPIService.kanbanMoveTask(
                boardSlug: boardSlug,
                taskID: taskID,
                statusRawValue: newStatus.rawValue
            )
            await reloadKanbanAfterOperation(taskID: taskID, boardSlug: boardSlug)
        } catch {
            // Revert optimistic update on failure
            if var board = kanbanBoard, let revert = revertTasks {
                board.tasks = revert
                kanbanBoard = board
            }
            kanbanError = error.localizedDescription
        }
    }

    func reclaimKanbanTask(taskID: String, reason: String?) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task reclaimed",
            failureMessage: "Unable to reclaim Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.reclaimTask(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                reason: reason
            )
        }
    }

    func reassignKanbanTask(taskID: String, assignee: String?, reclaimFirst: Bool, reason: String?) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task reassigned",
            failureMessage: "Unable to reassign Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.reassignTask(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                assignee: assignee,
                reclaimFirst: reclaimFirst,
                reason: reason
            )
        }
    }

    func editKanbanTaskResult(taskID: String, result: String, summary: String?, metadataJSON: String?) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task result edited",
            failureMessage: "Unable to edit Kanban task result"
        ) { profile, boardSlug in
            try await kanbanBrowserService.editCompletedTaskResult(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                result: result,
                summary: summary,
                metadataJSON: metadataJSON
            )
        }
    }

    func archiveKanbanTask(taskID: String) async {
        await operateOnKanbanTask(
            taskID: taskID,
            successMessage: "Kanban task archived",
            failureMessage: "Unable to archive Kanban task"
        ) { profile, boardSlug in
            try await kanbanBrowserService.archiveTask(connection: profile, boardSlug: boardSlug, taskID: taskID)
        }
    }

    func deleteKanbanTask(taskID: String) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnKanbanTask else { return }

        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskID
        kanbanError = nil

        do {
            let boardSlug = selectedKanbanBoardSlug
            try await kanbanBrowserService.deleteTask(connection: profile, boardSlug: boardSlug, taskID: taskID)
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return }
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            if selectedKanbanTaskID == nil {
                selectedKanbanTaskDetail = nil
            }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            setStatusMessage(L10n.string("Kanban task deleted"))
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to delete Kanban task"))
        }
    }

    /// Nudges the dispatcher for a specific task by posting a dispatch comment/event.
    /// Uses the Dashboard API when available; falls back to adding an SSH comment.
    func nudgeKanbanTask(taskId: String) async {
        guard !isOperatingOnKanbanTask else { return }
        let boardSlug = selectedKanbanBoardSlug

        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskId
        kanbanError = nil
        setStatusMessage(L10n.string("Nudging task dispatcher…"))

        if dashboardAPIAvailable {
            do {
                let body: [String: String] = ["board": boardSlug, "task_id": taskId]
                let payload = try JSONSerialization.data(withJSONObject: body)
                _ = try await dashboardAPIService.authenticatedPost(
                    path: "api/plugins/kanban/dispatch",
                    body: payload
                )
                await reloadKanbanAfterOperation(taskID: taskId, boardSlug: boardSlug)
                isOperatingOnKanbanTask = false
                operatingKanbanTaskID = nil
                setStatusMessage(L10n.string("Dispatcher nudged for task"))
                return
            } catch {
                // Fall through to SSH comment path
            }
        }

        // SSH fallback: post a comment to the task requesting dispatcher attention
        guard let profile = activeConnection else {
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            return
        }

        do {
            try await kanbanBrowserService.addComment(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskId,
                body: "[nudge] Please pick up this task."
            )
            await reloadKanbanAfterOperation(taskID: taskId, boardSlug: boardSlug)
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            setStatusMessage(L10n.string("Dispatcher nudged for task"))
        } catch {
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to nudge task dispatcher"))
        }
    }

    func dispatchKanbanNow() async {
        guard let profile = activeConnection else { return }
        guard !isDispatchingKanban else { return }

        isDispatchingKanban = true
        kanbanError = nil
        setStatusMessage(L10n.string("Nudging Kanban dispatcher..."))

        do {
            let boardSlug = selectedKanbanBoardSlug
            let result = try await kanbanBrowserService.dispatchNow(connection: profile, boardSlug: boardSlug)
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return }
            await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
            isDispatchingKanban = false

            if let result {
                setStatusMessage(
                    L10n.string(
                        "Kanban dispatch: %@ spawned, %@ promoted",
                        "\(result.spawned.count)",
                        "\(result.promoted)"
                    )
                )
            } else {
                setStatusMessage(L10n.string("Kanban dispatcher nudged"))
            }
        } catch {
            guard isActiveWorkspace(profile) else { return }
            isDispatchingKanban = false
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to nudge Kanban dispatcher"))
        }
    }

    func setKanbanHomeSubscription(
        taskID: String,
        homeChannel: KanbanHomeChannel,
        subscribed: Bool
    ) async -> Bool {
        guard let profile = activeConnection else { return false }
        guard !isOperatingOnKanbanTask else { return false }

        let boardSlug = selectedKanbanBoardSlug
        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskID
        kanbanError = nil

        do {
            try await kanbanBrowserService.setHomeSubscription(
                connection: profile,
                boardSlug: boardSlug,
                taskID: taskID,
                homeChannel: homeChannel,
                subscribed: subscribed
            )
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return false }
            await loadKanbanTaskDetail(taskID: taskID)
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            setStatusMessage(subscribed ? L10n.string("Home channel subscribed") : L10n.string("Home channel unsubscribed"))
            return true
        } catch {
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return false }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to update Kanban home channel"))
            return false
        }
    }

    // MARK: - Kanban Plugin: Decompose, Log, Orchestration, Bulk

    /// POST /api/plugins/kanban/tasks/{task_id}/decompose
    /// Decomposes the selected task into subtasks via LLM. HTTP-only (requires dashboard access).
    func decomposeKanbanTask(_ taskID: String) async {
        guard dashboardAPIAvailable else {
            kanbanError = L10n.string("Dashboard API is not available. Connect via SSH tunnel or local connection to use decompose.")
            return
        }
        let boardSlug = selectedKanbanBoardSlug
        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskID
        kanbanError = nil
        setStatusMessage(L10n.string("Decomposing task…"))

        do {
            try await dashboardAPIService.kanbanDecomposeTask(taskID: taskID, boardSlug: boardSlug)
            await reloadKanbanAfterOperation(taskID: taskID, boardSlug: boardSlug)
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            setStatusMessage(L10n.string("Task decomposed into subtasks"))
        } catch {
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to decompose task"))
        }
    }

    /// GET /api/plugins/kanban/tasks/{task_id}/log
    /// Loads the worker stdout/stderr log for the given task. Prefers HTTP; falls back to the
    /// workerLog field already present in task detail (SSH path).
    func viewKanbanTaskLog(_ taskID: String) async {
        guard !isLoadingKanbanLog else { return }
        kanbanTaskLog = nil
        isLoadingKanbanLog = true
        kanbanError = nil

        // Prefer HTTP API when dashboard is available
        if dashboardAPIAvailable {
            let boardSlug = selectedKanbanBoardSlug
            do {
                let log = try await dashboardAPIService.kanbanGetTaskLog(taskID: taskID, boardSlug: boardSlug)
                isLoadingKanbanLog = false
                kanbanTaskLog = log.isEmpty ? L10n.string("(No log output)") : log
                return
            } catch {
                // Fall through to SSH path
            }
        }

        // SSH fallback: use the workerLog already loaded in selectedKanbanTaskDetail
        if let existingLog = selectedKanbanTaskDetail?.workerLog,
           !existingLog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            kanbanTaskLog = existingLog
            isLoadingKanbanLog = false
            return
        }

        // Try reloading task detail over SSH to pick up workerLog
        if let profile = activeConnection {
            let boardSlug = selectedKanbanBoardSlug
            do {
                let detail = try await kanbanBrowserService.loadTaskDetail(
                    connection: profile,
                    boardSlug: boardSlug,
                    taskID: taskID
                )
                isLoadingKanbanLog = false
                let trimmedLog = detail.workerLog?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                kanbanTaskLog = trimmedLog.isEmpty ? L10n.string("(No log output)") : trimmedLog
                return
            } catch {
                isLoadingKanbanLog = false
                kanbanTaskLog = nil
                kanbanError = error.localizedDescription
                return
            }
        }

        isLoadingKanbanLog = false
        kanbanTaskLog = L10n.string("(No log output)")
    }

    /// GET /api/plugins/kanban/orchestration
    /// Loads orchestration config. Requires dashboard API access.
    func loadKanbanOrchestration() async {
        guard dashboardAPIAvailable else { return }
        guard !isLoadingKanbanOrchestration else { return }

        isLoadingKanbanOrchestration = true
        kanbanOrchestrationError = nil

        do {
            let config = try await dashboardAPIService.kanbanGetOrchestration()
            isLoadingKanbanOrchestration = false
            kanbanOrchestration = config
        } catch {
            isLoadingKanbanOrchestration = false
            kanbanOrchestrationError = error.localizedDescription
        }
    }

    /// PUT /api/plugins/kanban/orchestration
    /// Saves orchestration config. Requires dashboard API access.
    func saveKanbanOrchestration(_ config: KanbanOrchestrationConfig) async {
        guard dashboardAPIAvailable else { return }

        isLoadingKanbanOrchestration = true
        kanbanOrchestrationError = nil
        setStatusMessage(L10n.string("Saving orchestration config…"))

        do {
            try await dashboardAPIService.kanbanUpdateOrchestration(config)
            kanbanOrchestration = config
            isLoadingKanbanOrchestration = false
            setStatusMessage(L10n.string("Orchestration config saved"))
        } catch {
            isLoadingKanbanOrchestration = false
            kanbanOrchestrationError = error.localizedDescription
            setStatusMessage(L10n.string("Unable to save orchestration config"))
        }
    }

    /// POST /api/plugins/kanban/tasks/bulk (HTTP) or individual SSH moves (fallback)
    func bulkUpdateKanbanTasks(_ taskIDs: [String], status: KanbanTaskStatus) async {
        guard !taskIDs.isEmpty else { return }
        let boardSlug = selectedKanbanBoardSlug
        kanbanError = nil

        if dashboardAPIAvailable {
            setStatusMessage(L10n.string("Updating %@ tasks…", "\(taskIDs.count)"))
            do {
                try await dashboardAPIService.kanbanBulkUpdateTasks(
                    taskIDs: taskIDs,
                    status: status,
                    boardSlug: boardSlug
                )
                kanbanSelectedTaskIDs = []
                await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
                setStatusMessage(L10n.string("Moved %@ tasks to %@", "\(taskIDs.count)", status.displayTitle))
            } catch {
                kanbanError = error.localizedDescription
                setStatusMessage(L10n.string("Bulk update failed"))
            }
        } else {
            // Bulk status change requires dashboard API. Show a helpful error.
            kanbanError = L10n.string("Bulk status update requires dashboard API access. Enable SSH tunnel or use a local connection.")
            setStatusMessage(L10n.string("Dashboard API required for bulk update"))
        }
    }

    // MARK: - Kanban helpers

    func reloadKanbanAfterOperation(taskID: String, boardSlug: String) async {
        await loadKanbanBoard(includeArchived: includeArchivedKanbanTasks)
        guard selectedKanbanBoardSlug == boardSlug else { return }
        if kanbanBoard?.tasks.contains(where: { $0.id == taskID }) == true {
            selectedKanbanTaskID = taskID
            await loadKanbanTaskDetail(taskID: taskID)
        }
    }

    private func operateOnKanbanTask(
        taskID: String,
        successMessage: String,
        failureMessage: String,
        operation: (ConnectionProfile, String) async throws -> Void
    ) async {
        guard let profile = activeConnection else { return }
        guard !isOperatingOnKanbanTask else { return }

        let boardSlug = selectedKanbanBoardSlug
        isOperatingOnKanbanTask = true
        operatingKanbanTaskID = taskID
        kanbanError = nil

        do {
            try await operation(profile, boardSlug)
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return }
            await reloadKanbanAfterOperation(taskID: taskID, boardSlug: boardSlug)
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            setStatusMessage(L10n.string(successMessage))
        } catch {
            guard isActiveWorkspace(profile), selectedKanbanBoardSlug == boardSlug else { return }
            isOperatingOnKanbanTask = false
            operatingKanbanTaskID = nil
            kanbanError = error.localizedDescription
            setStatusMessage(L10n.string(failureMessage))
        }
    }
}
