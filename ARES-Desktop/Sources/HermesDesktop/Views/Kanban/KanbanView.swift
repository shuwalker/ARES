import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct KanbanView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var splitLayout: HermesSplitLayout

    @State private var searchText = ""
    @State private var statusFilter: KanbanStatusFilter = .all
    @State private var assigneeFilter = KanbanFilterOption.all
    @State private var tenantFilter = KanbanFilterOption.all
    @State private var isCreatingTask = false
    @State private var isCreatingBoard = false
    @State private var taskDraft = KanbanTaskDraft()
    @State private var boardDraft = KanbanBoardDraft()
    @State private var boardPendingArchive: KanbanProject?
    @State private var showArchiveBoardConfirmation = false
    @State private var showOrchestrationSheet = false
    @State private var orchestrationDraft = KanbanOrchestrationDraft()

    var body: some View {
        HermesCollapsibleHSplitView(layout: $splitLayout, detailMinWidth: 420) {
            primaryContent
        } detail: {
            detailContent
                .hermesSplitDetailColumn(minWidth: 420, idealWidth: 560)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task(id: appState.activeConnectionID) {
            await appState.loadKanbanBoards()
            if appState.kanbanBoard == nil {
                await appState.loadKanbanBoard()
            }
        }
        .onChange(of: appState.includeArchivedKanbanTasks) { _, includeArchived in
            Task { await appState.refreshKanbanBoard(includeArchived: includeArchived) }
        }
        .onChange(of: statusFilter) { _, filter in
            if filter == .archived, !appState.includeArchivedKanbanTasks {
                appState.includeArchivedKanbanTasks = true
            }
        }
        .alert(L10n.string("Archive this Kanban board?"), isPresented: $showArchiveBoardConfirmation, presenting: boardPendingArchive) { board in
            Button(L10n.string("Archive"), role: .destructive) {
                Task { await appState.archiveKanbanBoard(board) }
            }
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: { board in
            Text(L10n.string("%@ will be moved out of the active board list. Existing task data stays recoverable on the remote host.", board.resolvedName))
        }
        .sheet(isPresented: $showOrchestrationSheet) {
            KanbanOrchestrationSheet(
                draft: $orchestrationDraft,
                config: appState.kanbanOrchestration,
                isLoading: appState.isLoadingKanbanOrchestration,
                errorMessage: appState.kanbanOrchestrationError,
                onSave: { draft in
                    let config = draft.toConfig()
                    Task { await appState.saveKanbanOrchestration(config) }
                },
                onDismiss: { showOrchestrationSheet = false }
            )
        }
        .onChange(of: showOrchestrationSheet) { _, isShowing in
            if isShowing {
                orchestrationDraft = KanbanOrchestrationDraft(from: appState.kanbanOrchestration)
                Task { await appState.loadKanbanOrchestration() }
            }
        }
    }

    private var primaryContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HermesPageHeader(
                title: "Kanban",
                subtitle: "Inspect and operate Hermes Kanban projects over SSH."
            ) {
                HermesExpandableSearchField(
                    text: $searchText,
                    prompt: L10n.string("Search tasks"),
                    expandedWidth: 220,
                    focusRequestID: appState.searchFocusRequestID
                )
                .fixedSize(horizontal: true, vertical: false)
            }

            kanbanToolbar
            boardContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.vertical, 20)
    }

    private var kanbanToolbar: some View {
        HermesWrappingFlowLayout(horizontalSpacing: 10, verticalSpacing: 8) {
            HStack(spacing: 8) {
                boardPicker
                statusPicker
                advancedFilterMenu
            }
            .fixedSize(horizontal: true, vertical: false)

            HStack(spacing: 8) {
                createTaskButton
                dispatchButton
                if appState.dashboardAPIAvailable {
                    orchestrationButton
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            if !appState.kanbanSelectedTaskIDs.isEmpty {
                bulkActionBar
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var orchestrationButton: some View {
        Button {
            showOrchestrationSheet = true
        } label: {
            Label(L10n.string("Orchestration"), systemImage: "gearshape.2")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .help(L10n.string("Orchestration settings"))
    }

    private var bulkActionBar: some View {
        HStack(spacing: 8) {
            Text(L10n.string("%@ selected", "\(appState.kanbanSelectedTaskIDs.count)"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Menu {
                Section {
                    ForEach(KanbanTaskStatus.boardStatuses, id: \.rawValue) { status in
                        Button(L10n.string(status.displayTitle)) {
                            let ids = Array(appState.kanbanSelectedTaskIDs)
                            Task { await appState.bulkUpdateKanbanTasks(ids, status: status) }
                        }
                    }
                } header: {
                    Text(L10n.string("Move to"))
                }
            } label: {
                Label(L10n.string("Move to…"), systemImage: "arrow.right.circle")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)

            Button {
                appState.kanbanSelectedTaskIDs = []
            } label: {
                Label(L10n.string("Clear"), systemImage: "xmark")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help(L10n.string("Clear selection"))
        }
    }

    private var boardPicker: some View {
        Menu {
            Section {
                ForEach(appState.kanbanBoards) { board in
                    Button {
                        isCreatingBoard = false
                        isCreatingTask = false
                        Task { await appState.selectKanbanBoard(board.slug) }
                    } label: {
                        HStack {
                            menuLabel(board.resolvedName, isSelected: board.slug == appState.selectedKanbanBoardSlug, shouldLocalize: false)
                            if board.taskTotal > 0 {
                                Text("\(board.taskTotal)")
                            }
                        }
                    }
                }
            } header: {
                Text(L10n.string("Boards"))
            }

            Divider()

            if appState.supportsKanbanBoardManagement {
                Button {
                    boardDraft = KanbanBoardDraft()
                    isCreatingTask = false
                    isCreatingBoard = true
                } label: {
                    Label(L10n.string("New Board"), systemImage: "plus")
                }
            } else {
                Text(L10n.string("Run hermes update to enable multiple boards"))
            }

            if appState.supportsKanbanBoardManagement,
               let selectedBoard = appState.selectedKanbanBoard,
               !selectedBoard.isDefault {
                Divider()

                Button(L10n.string("Archive Board"), role: .destructive) {
                    boardPendingArchive = selectedBoard
                    showArchiveBoardConfirmation = true
                }
                .disabled(appState.isOperatingOnKanbanBoard)
            }
        } label: {
            KanbanToolbarMenuLabel(
                title: "Board",
                value: selectedBoardTitle,
                systemImage: "rectangle.3.group",
                width: 172
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(appState.isLoadingKanbanBoards || appState.isSavingKanbanBoardDraft || appState.isOperatingOnKanbanBoard)
        .help(L10n.string("Select Kanban board"))
    }

    private var statusPicker: some View {
        Menu {
            Section {
                ForEach(KanbanStatusFilter.allCases, id: \.self) { option in
                    Button {
                        statusFilter = option
                    } label: {
                        menuLabel(option.title, isSelected: statusFilter == option)
                    }
                }
            } header: {
                Text(L10n.string("Status"))
            }
        } label: {
            KanbanToolbarMenuLabel(
                title: "Status",
                value: L10n.string(statusFilter.title),
                systemImage: "circle.dashed.inset.filled",
                width: 136
            )
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    private var createTaskButton: some View {
        Button {
            startCreatingTask()
        } label: {
            Label(L10n.string("New Task"), systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .fixedSize(horizontal: true, vertical: false)
        .help(L10n.string("Create a Kanban task"))
        .disabled(appState.isSavingKanbanTaskDraft || appState.isOperatingOnKanbanTask)
    }

    private var dispatchButton: some View {
        Button {
            Task { await appState.dispatchKanbanNow() }
        } label: {
            if appState.isDispatchingKanban {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
            } else {
                Label(L10n.string("Nudge dispatcher"), systemImage: "bolt")
                    .labelStyle(.iconOnly)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .help(L10n.string("Nudge dispatcher"))
        .disabled(appState.isDispatchingKanban || appState.isLoadingKanbanBoard)
    }

    private var advancedFilterMenu: some View {
        Menu {
            Section {
                Button {
                    assigneeFilter = .all
                } label: {
                    menuLabel("All assignees", isSelected: assigneeFilter == .all)
                }

                ForEach(assigneeOptions, id: \.self) { assignee in
                    Button {
                        assigneeFilter = .value(assignee)
                    } label: {
                        menuLabel(assignee, isSelected: assigneeFilter == .value(assignee), shouldLocalize: false)
                    }
                }
            } header: {
                Text(L10n.string("Assignee"))
            }

            Section {
                Button {
                    tenantFilter = .all
                } label: {
                    menuLabel("All tenants", isSelected: tenantFilter == .all)
                }

                ForEach(tenantOptions, id: \.self) { tenant in
                    Button {
                        tenantFilter = .value(tenant)
                    } label: {
                        menuLabel(tenant, isSelected: tenantFilter == .value(tenant), shouldLocalize: false)
                    }
                }
            } header: {
                Text(L10n.string("Tenant"))
            }

            Divider()

            Button {
                appState.includeArchivedKanbanTasks.toggle()
            } label: {
                menuLabel("Archived", isSelected: appState.includeArchivedKanbanTasks)
            }
        } label: {
            Label {
                HStack(spacing: 6) {
                    Text(L10n.string("Filter"))

                    if activeAdvancedFilterCount > 0 {
                        Text("\(activeAdvancedFilterCount)")
                            .font(.caption2.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.accentColor, in: Capsule())
                    }
                }
            } icon: {
                Image(systemName: hasAdvancedFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .tint(hasAdvancedFilters ? .accentColor : nil)
    }

    private func menuLabel(_ text: String, isSelected: Bool, shouldLocalize: Bool = true) -> some View {
        Group {
            if isSelected {
                Label(shouldLocalize ? L10n.string(text) : text, systemImage: "checkmark")
            } else {
                Text(shouldLocalize ? L10n.string(text) : text)
            }
        }
    }

    private var hasAdvancedFilters: Bool {
        activeAdvancedFilterCount > 0
    }

    private var activeAdvancedFilterCount: Int {
        var count = 0
        if assigneeFilter != .all { count += 1 }
        if tenantFilter != .all { count += 1 }
        if appState.includeArchivedKanbanTasks { count += 1 }
        return count
    }

    private var isFilteringTasks: Bool {
        statusFilter != .all ||
            assigneeFilter != .all ||
            tenantFilter != .all ||
            !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            appState.includeArchivedKanbanTasks
    }

    private var selectedBoardTitle: String {
        appState.selectedKanbanBoard?.resolvedName ?? L10n.string("Default")
    }

    @ViewBuilder
    private var boardContent: some View {
        if (appState.isLoadingKanbanBoards || appState.isLoadingKanbanBoard) && appState.kanbanBoard == nil {
            HermesSurfacePanel {
                HermesLoadingState(
                    label: "Loading Kanban board...",
                    minHeight: 320
                )
            }
        } else if let error = appState.kanbanError, appState.kanbanBoard == nil {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("Unable to load Kanban"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 320)
            }
        } else if let board = appState.kanbanBoard, !board.isInitialized {
            HermesSurfacePanel {
                VStack(alignment: .leading, spacing: 18) {
                    ContentUnavailableView(
                        L10n.string("No Kanban board yet"),
                        systemImage: "rectangle.3.group",
                        description: Text(L10n.string("No Kanban database exists at %@. Create the first task to initialize this board on the remote host.", board.databasePath))
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)

                    Button {
                        startCreatingTask()
                    } label: {
                        Label(L10n.string("Create First Task"), systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appState.isSavingKanbanTaskDraft)
                }
            }
        } else if let board = appState.kanbanBoard {
            HermesSurfacePanel(
                title: panelTitle,
                subtitle: boardSubtitle(board)
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    if let warning = dispatcherWarning(for: board) {
                        KanbanWarningBanner(message: warning)
                    }

                    if let error = appState.kanbanError {
                        Text(error)
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }

                    if filteredTasks.isEmpty {
                        KanbanEmptyTaskState(
                            isFiltering: isFilteringTasks,
                            isSaving: appState.isSavingKanbanTaskDraft,
                            onCreate: startCreatingTask
                        )
                    } else {
                        ScrollView {
                            kanbanGroupedList(board)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .overlay(alignment: .topTrailing) {
                if appState.isLoadingKanbanBoard && !appState.isRefreshingKanbanBoard {
                    HermesLoadingOverlay()
                        .padding(18)
                }
            }
        }
    }

    private func kanbanBoardLayout(_ board: KanbanBoard) -> some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(displayStatuses, id: \.rawValue) { status in
                    KanbanColumnView(
                        status: status,
                        tasks: filteredTasks(for: status),
                        selectedTaskID: appState.selectedKanbanTaskID,
                        onSelect: selectTask,
                        onDrop: { taskID in
                            guard appState.dashboardAPIAvailable else { return }
                            let task = appState.kanbanBoard?.tasks.first(where: { $0.id == taskID })
                            guard task?.status != status, status != .archived else { return }
                            Task { await appState.moveKanbanTask(taskID: taskID, toStatus: status) }
                        },
                        onNudge: { task in
                            Task { await appState.nudgeKanbanTask(taskId: task.id) }
                        }
                    )
                    .frame(width: 250)
                }
            }
            .padding(.bottom, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func kanbanGroupedList(_ board: KanbanBoard) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(displayStatuses, id: \.rawValue) { status in
                let tasks = filteredTasks(for: status)
                if !tasks.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Text(L10n.string(status.displayTitle))
                                .font(.headline)

                            HermesBadge(text: "\(tasks.count)", tint: KanbanColors.tint(for: status))
                        }

                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(tasks) { task in
                                KanbanTaskCard(
                                    task: task,
                                    isSelected: task.id == appState.selectedKanbanTaskID,
                                    isChecked: appState.kanbanSelectedTaskIDs.contains(task.id),
                                    onSelect: { selectTask(task) },
                                    onToggleCheck: {
                                        if appState.kanbanSelectedTaskIDs.contains(task.id) {
                                            appState.kanbanSelectedTaskIDs.remove(task.id)
                                        } else {
                                            appState.kanbanSelectedTaskIDs.insert(task.id)
                                        }
                                    },
                                    onNudge: {
                                        Task { await appState.nudgeKanbanTask(taskId: task.id) }
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var detailContent: some View {
        if isCreatingBoard {
            KanbanBoardEditorView(
                draft: $boardDraft,
                errorMessage: appState.kanbanError,
                isSaving: appState.isSavingKanbanBoardDraft,
                onCancel: {
                    isCreatingBoard = false
                },
                onSave: {
                    if await appState.createKanbanBoard(boardDraft) {
                        isCreatingBoard = false
                    }
                }
            )
        } else if isCreatingTask {
            KanbanTaskEditorView(
                draft: $taskDraft,
                errorMessage: appState.kanbanError,
                isSaving: appState.isSavingKanbanTaskDraft,
                assignees: assigneeOptions,
                onCancel: {
                    isCreatingTask = false
                },
                onSave: {
                    if await appState.createKanbanTask(taskDraft) {
                        isCreatingTask = false
                    }
                }
            )
        } else {
            KanbanTaskDetailView(
                task: selectedTask,
                detail: appState.selectedKanbanTaskDetail,
                errorMessage: appState.kanbanError,
                isLoading: appState.isLoadingKanbanTaskDetail,
                operationInFlight: selectedTask.map { task in
                    appState.isOperatingOnKanbanTask && appState.operatingKanbanTaskID == task.id
                } ?? false,
                assignees: assigneeOptions,
                dashboardAPIAvailable: appState.dashboardAPIAvailable,
                isLoadingLog: appState.isLoadingKanbanLog,
                taskLog: appState.kanbanTaskLog,
                onCreate: {
                    taskDraft = KanbanTaskDraft()
                    isCreatingBoard = false
                    isCreatingTask = true
                },
                onSpecify: { taskID in
                    await appState.specifyKanbanTask(taskID: taskID)
                },
                onAssign: { taskID, assignee in
                    await appState.assignKanbanTask(taskID: taskID, assignee: assignee)
                },
                onUpdateFields: { taskID, body, tenant, priority, skills in
                    await appState.updateKanbanTaskFields(
                        taskID: taskID,
                        body: body,
                        tenant: tenant,
                        priority: priority,
                        skills: skills
                    )
                },
                onSetParents: { taskID, parentIDs in
                    await appState.setKanbanTaskParents(taskID: taskID, parentIDs: parentIDs)
                },
                onSetChildren: { taskID, childIDs in
                    await appState.setKanbanTaskChildren(taskID: taskID, childIDs: childIDs)
                },
                onComment: { taskID, comment in
                    await appState.addKanbanComment(taskID: taskID, body: comment)
                },
                onBlock: { taskID, reason in
                    await appState.blockKanbanTask(taskID: taskID, reason: reason)
                },
                onUnblock: { taskID in
                    await appState.unblockKanbanTask(taskID: taskID)
                },
                onComplete: { taskID, result in
                    await appState.completeKanbanTask(taskID: taskID, result: result)
                },
                onReclaim: { taskID, reason in
                    await appState.reclaimKanbanTask(taskID: taskID, reason: reason)
                },
                onReassign: { taskID, assignee, reclaimFirst, reason in
                    await appState.reassignKanbanTask(
                        taskID: taskID,
                        assignee: assignee,
                        reclaimFirst: reclaimFirst,
                        reason: reason
                    )
                },
                onEditResult: { taskID, result, summary, metadataJSON in
                    await appState.editKanbanTaskResult(
                        taskID: taskID,
                        result: result,
                        summary: summary,
                        metadataJSON: metadataJSON
                    )
                },
                onArchive: { taskID in
                    await appState.archiveKanbanTask(taskID: taskID)
                },
                onDelete: { taskID in
                    await appState.deleteKanbanTask(taskID: taskID)
                },
                onSetHomeSubscription: { taskID, homeChannel, subscribed in
                    await appState.setKanbanHomeSubscription(
                        taskID: taskID,
                        homeChannel: homeChannel,
                        subscribed: subscribed
                    )
                },
                onDecompose: { taskID in
                    await appState.decomposeKanbanTask(taskID)
                },
                onViewLog: { taskID in
                    await appState.viewKanbanTaskLog(taskID)
                }
            )
        }
    }

    private var filteredTasks: [KanbanTask] {
        guard let board = appState.kanbanBoard else { return [] }
        return board.tasks.filter { task in
            if !appState.includeArchivedKanbanTasks && task.status == .archived {
                return false
            }
            if let status = statusFilter.status, task.status != status {
                return false
            }
            if case .value(let assignee) = assigneeFilter, task.assignee != assignee {
                return false
            }
            if case .value(let tenant) = tenantFilter, task.tenant != tenant {
                return false
            }
            return task.matchesSearch(searchText)
        }
    }

    private func filteredTasks(for status: KanbanTaskStatus) -> [KanbanTask] {
        filteredTasks.filter { $0.status == status }
    }

    private var displayStatuses: [KanbanTaskStatus] {
        if let status = statusFilter.status {
            return [status]
        }

        return KanbanTaskStatus.boardStatuses.filter { status in
            status != .archived || appState.includeArchivedKanbanTasks
        }
    }

    private var assigneeOptions: [String] {
        let boardAssignees = appState.kanbanBoard?.assignees.map(\.name) ?? []
        let taskAssignees = appState.kanbanBoard?.tasks.compactMap(\.assignee) ?? []
        return Array(Set(boardAssignees + taskAssignees)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private var tenantOptions: [String] {
        let boardTenants = appState.kanbanBoard?.tenants ?? []
        let taskTenants = appState.kanbanBoard?.tasks.compactMap(\.tenant) ?? []
        return Array(Set(boardTenants + taskTenants)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    private var selectedTask: KanbanTask? {
        appState.kanbanBoard?.task(id: appState.selectedKanbanTaskID)
    }

    private var panelTitle: String {
        let total = appState.kanbanBoard?.tasks.count ?? 0
        let filtered = filteredTasks.count

        if isFilteringTasks {
            return L10n.string("Kanban Tasks (%@ of %@)", "\(filtered)", "\(total)")
        }

        return L10n.string("Kanban Tasks (%@)", "\(total)")
    }

    private func boardSubtitle(_ board: KanbanBoard) -> String {
        let boardName = appState.selectedKanbanBoard?.resolvedName ?? selectedBoardTitle
        return L10n.string(
            "Kanban board %@ at %@. SSH-native; active profile is the operator.",
            boardName,
            board.databasePath
        )
    }

    private func dispatcherWarning(for board: KanbanBoard) -> String? {
        guard board.tasks.contains(where: { $0.status == .ready }) else { return nil }
        guard board.dispatcher?.isKnownInactive == true else { return nil }
        return board.dispatcher?.message ?? "Ready tasks are waiting, but the remote Hermes dispatcher does not appear to be active."
    }

    private func selectTask(_ task: KanbanTask) {
        Task { await appState.loadKanbanTaskDetail(taskID: task.id) }
    }

    private func startCreatingTask() {
        taskDraft = KanbanTaskDraft()
        isCreatingBoard = false
        isCreatingTask = true
    }
}

// MARK: - Private enums used only within KanbanView

private enum KanbanStatusFilter: Hashable, CaseIterable {
    case all
    case triage
    case todo
    case ready
    case running
    case blocked
    case done
    case archived

    var title: String {
        switch self {
        case .all:
            "All"
        case .triage:
            "Triage"
        case .todo:
            "Todo"
        case .ready:
            "Ready"
        case .running:
            "Running"
        case .blocked:
            "Blocked"
        case .done:
            "Done"
        case .archived:
            "Archived"
        }
    }

    var status: KanbanTaskStatus? {
        switch self {
        case .all:
            nil
        case .triage:
            .triage
        case .todo:
            .todo
        case .ready:
            .ready
        case .running:
            .running
        case .blocked:
            .blocked
        case .done:
            .done
        case .archived:
            .archived
        }
    }
}

private enum KanbanFilterOption: Hashable {
    case all
    case value(String)

    var displayTitle: String {
        switch self {
        case .all:
            L10n.string("All")
        case .value(let value):
            value
        }
    }
}

// MARK: - Module-level enums used across Kanban files

enum KanbanActionKind: Hashable {
    case specify
    case details
    case parents
    case children
    case assign
    case comment
    case complete
    case recovery
    case editResult
    case block
}

enum KanbanColors {
    static func tint(for status: KanbanTaskStatus) -> Color {
        switch status {
        case .triage:
            .secondary
        case .todo:
            .blue
        case .ready:
            .green
        case .running:
            .orange
        case .blocked:
            .red
        case .done:
            .purple
        case .archived:
            .secondary
        case .other:
            .secondary
        }
    }
}
