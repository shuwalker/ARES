import AppKit
import SwiftUI

struct KanbanTaskDetailView: View {
    let task: KanbanTask?
    let detail: KanbanTaskDetail?
    let errorMessage: String?
    let isLoading: Bool
    let operationInFlight: Bool
    let assignees: [String]
    let dashboardAPIAvailable: Bool
    let isLoadingLog: Bool
    let taskLog: String?
    let onCreate: () -> Void
    let onSpecify: (String) async -> Void
    let onAssign: (String, String?) async -> Void
    let onUpdateFields: (String, String, String, Int, [String]) async -> Void
    let onSetParents: (String, [String]) async -> Void
    let onSetChildren: (String, [String]) async -> Void
    let onComment: (String, String) async -> Bool
    let onBlock: (String, String?) async -> Void
    let onUnblock: (String) async -> Void
    let onComplete: (String, String?) async -> Void
    let onReclaim: (String, String?) async -> Void
    let onReassign: (String, String?, Bool, String?) async -> Void
    let onEditResult: (String, String, String?, String?) async -> Void
    let onArchive: (String) async -> Void
    let onDelete: (String) async -> Void
    let onSetHomeSubscription: (String, KanbanHomeChannel, Bool) async -> Bool
    let onDecompose: (String) async -> Void
    let onViewLog: (String) async -> Void

    @State private var draft = KanbanActionDraft()
    @State private var showArchiveConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var expandedAction: KanbanActionKind?
    @State private var showLogSheet = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let task {
                    headerPanel(task)

                    if let errorMessage {
                        KanbanWarningBanner(message: errorMessage)
                    }

                    if isLoading && detail == nil {
                        HermesSurfacePanel {
                            HermesLoadingState(label: "Loading task detail...", minHeight: 180)
                        }
                    } else {
                        metadataPanel(task)
                        actionPanel(task)
                        recoveryWarningPanel(task)

                        if let body = task.trimmedBody {
                            HermesSurfacePanel(
                                title: "Body",
                                subtitle: "Task description stored on the remote board."
                            ) {
                                HermesInsetSurface {
                                    Text(body)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                            }
                        }

                        if let result = task.trimmedResult {
                            HermesSurfacePanel(
                                title: "Result",
                                subtitle: "Completion handoff stored by Hermes."
                            ) {
                                HermesInsetSurface {
                                    Text(result)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .textSelection(.enabled)
                                }
                            }
                        }

                        if let detail {
                            homeChannelsPanel(task, detail)
                            linksPanel(detail)
                            commentsPanel(task, detail)
                            runsPanel(detail)
                            eventsPanel(detail)
                            logPanel(detail)
                        }
                    }
                } else {
                    HermesSurfacePanel {
                        VStack(alignment: .leading, spacing: 18) {
                            let emptyLabel = L10n.string("Select a Kanban task"); let emptySystemImage = "rectangle.3.group"
                            ContentUnavailableView(
                                emptyLabel,
                                systemImage: emptySystemImage,
                                description: Text(L10n.string("Choose a task from the selected board, or create a new one."))
                            )
                            .frame(maxWidth: .infinity, minHeight: 280)

                            Button {
                                onCreate()
                            } label: {
                                Label(L10n.string("Create Kanban Task"), systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)
        }
        .onChange(of: task?.id) { _, _ in
            resetDraft()
            expandedAction = nil
        }
        .onChange(of: detail?.parentIDs) { _, _ in
            resetDraft()
        }
        .onChange(of: detail?.childIDs) { _, _ in
            resetDraft()
        }
        .onAppear {
            resetDraft()
        }
        .alert(L10n.string("Archive this task?"), isPresented: $showArchiveConfirmation, presenting: task) { task in
            Button(L10n.string("Archive"), role: .destructive) {
                Task { await onArchive(task.id) }
            }
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: { task in
            Text(L10n.string("%@ will be hidden from the active board unless archived tasks are shown.", task.resolvedTitle))
        }
        .alert(L10n.string("Delete this task?"), isPresented: $showDeleteConfirmation, presenting: task) { task in
            Button(L10n.string("Delete"), role: .destructive) {
                Task { await onDelete(task.id) }
            }
            Button(L10n.string("Cancel"), role: .cancel) {}
        } message: { task in
            Text(L10n.string("%@ will be permanently removed from the remote Kanban database, including comments, links, events, and run history. Remote workspace files are left untouched.", task.resolvedTitle))
        }
        .sheet(isPresented: $showLogSheet) {
            KanbanTaskLogSheet(
                taskTitle: task?.resolvedTitle ?? "",
                log: taskLog,
                isLoading: isLoadingLog,
                onDismiss: { showLogSheet = false }
            )
        }
    }

    private func resetDraft() {
        draft = KanbanActionDraft(
            comment: "",
            result: task?.trimmedResult ?? "",
            blockReason: "",
            recoveryReason: "",
            recoverySummary: task?.trimmedResult ?? "",
            recoveryMetadata: "",
            reclaimBeforeReassign: task?.isRunning == true,
            assignee: task?.assignee ?? "",
            body: task?.trimmedBody ?? "",
            tenant: task?.tenant ?? "",
            priority: task?.priority ?? 0,
            skillsText: KanbanTaskDraft.listText(task?.skills ?? []),
            parentIDsText: KanbanTaskDraft.listText(detail?.parentIDs ?? task?.parentIDs ?? []),
            childIDsText: KanbanTaskDraft.listText(detail?.childIDs ?? task?.childIDs ?? [])
        )
    }

    private func headerPanel(_ task: KanbanTask) -> some View {
        HermesSurfacePanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(task.resolvedTitle)
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(task.id)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .contextMenu {
                                Button(L10n.string("Copy Task ID")) {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(task.id, forType: .string)
                                }
                            }
                    }

                    Spacer(minLength: 12)

                    HStack(spacing: 8) {
                        HermesBadge(text: task.status.displayTitle, tint: KanbanColors.tint(for: task.status))
                        HermesBadge(text: task.priorityLabel, tint: task.priority == 0 ? .secondary : .orange, isMonospaced: true)
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        primaryActions(task)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        primaryActions(task)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func primaryActions(_ task: KanbanTask) -> some View {
        if task.canUnblock {
            Button(L10n.string("Unblock")) {
                Task { await onUnblock(task.id) }
            }
            .buttonStyle(.borderedProminent)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(operationInFlight)
        }

        if task.canSpecify {
            Button(L10n.string("Specify")) {
                toggleAction(.specify)
            }
            .buttonStyle(.borderedProminent)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(operationInFlight)
        }

        if task.canComplete {
            if task.status == .blocked {
                Button(L10n.string("Complete")) {
                    toggleAction(.complete)
                }
                .buttonStyle(.bordered)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(operationInFlight)
            } else {
                Button(L10n.string("Complete")) {
                    toggleAction(.complete)
                }
                .buttonStyle(.borderedProminent)
                .fixedSize(horizontal: true, vertical: false)
                .disabled(operationInFlight)
            }
        }

        if task.canBlock {
            Button(L10n.string("Block")) {
                toggleAction(.block)
            }
            .buttonStyle(.bordered)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(operationInFlight)
        }

        Button {
            showLogSheet = true
            Task { await onViewLog(task.id) }
        } label: {
            if isLoadingLog {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 14, height: 14)
            } else {
                Label(L10n.string("View Log"), systemImage: "doc.text.magnifyingglass")
                    .labelStyle(.iconOnly)
            }
        }
        .buttonStyle(.bordered)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(operationInFlight || isLoadingLog)
        .help(L10n.string("View worker log"))

        if dashboardAPIAvailable && (task.status == .triage || task.status == .todo) {
            Button {
                Task { await onDecompose(task.id) }
            } label: {
                Label(L10n.string("Decompose"), systemImage: "arrow.triangle.branch")
            }
            .buttonStyle(.bordered)
            .fixedSize(horizontal: true, vertical: false)
            .disabled(operationInFlight)
            .help(L10n.string("LLM-decompose task into subtasks"))
        }

        Menu {
            Button(L10n.string("Archive"), role: .destructive) {
                showArchiveConfirmation = true
            }
            .disabled(task.status == .archived)

            Button(L10n.string("Delete"), role: .destructive) {
                showDeleteConfirmation = true
            }
        } label: {
            Label(L10n.string("More"), systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.bordered)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(operationInFlight)
        .help(L10n.string("More task actions"))

        if operationInFlight {
            ProgressView()
                .controlSize(.small)
        }
    }

    private func metadataPanel(_ task: KanbanTask) -> some View {
        HermesSurfacePanel(
            title: "Details",
            subtitle: "Board metadata from the remote host."
        ) {
            HermesInspectorFieldList(fields: metadataFields(for: task))

            if !task.skills.isEmpty {
                Divider()
                    .opacity(0.5)

                HermesWrappingFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(task.skills, id: \.self) { skill in
                        HermesBadge(text: skill, tint: .accentColor, isMonospaced: true)
                    }
                }
            }

            if let lastSpawnError = task.lastSpawnError {
                Divider()
                    .opacity(0.5)

                KanbanWarningBanner(message: lastSpawnError)
            }
        }
    }

    private func metadataFields(for task: KanbanTask) -> [HermesInspectorField] {
        var fields = [
            HermesInspectorField(
                id: "status",
                label: "Status",
                value: L10n.string(task.status.displayTitle),
                emphasizeValue: true
            ),
            HermesInspectorField(
                id: "assignee",
                label: "Assignee",
                value: task.assignee ?? L10n.string("Unassigned"),
                isMonospaced: task.assignee != nil
            ),
            HermesInspectorField(
                id: "priority",
                label: "Priority",
                value: "\(task.priority)",
                isMonospaced: true
            ),
            HermesInspectorField(
                id: "max-retries",
                label: "Max retries",
                value: task.maxRetries.map(String.init) ?? L10n.string("Board default"),
                isMonospaced: task.maxRetries != nil
            ),
            HermesInspectorField(
                id: "workspace",
                label: "Workspace",
                value: L10n.string(task.workspaceKind.displayTitle)
            )
        ]

        if let workspacePath = task.workspacePath {
            fields.append(HermesInspectorField(
                id: "workspace-path",
                label: "Workspace path",
                value: workspacePath,
                isMonospaced: true
            ))
        }

        if let progress = task.progressLabel {
            fields.append(HermesInspectorField(
                id: "child-progress",
                label: "Child progress",
                value: progress,
                isMonospaced: true
            ))
        }

        if let tenant = task.tenant {
            fields.append(HermesInspectorField(
                id: "tenant",
                label: "Tenant",
                value: tenant,
                isMonospaced: true
            ))
        }

        if let createdBy = task.createdBy {
            fields.append(HermesInspectorField(
                id: "created-by",
                label: "Created by",
                value: createdBy,
                isMonospaced: true
            ))
        }

        if let created = task.createdDate {
            fields.append(HermesInspectorField(
                id: "created",
                label: "Created",
                value: DateFormatters.shortDateTimeFormatter().string(from: created)
            ))
        }

        if let latest = task.latestActivityDate {
            fields.append(HermesInspectorField(
                id: "latest-activity",
                label: "Latest activity",
                value: DateFormatters.shortDateTimeFormatter().string(from: latest)
            ))
        }

        if let workerPID = task.workerPID {
            fields.append(HermesInspectorField(
                id: "worker-pid",
                label: "Worker PID",
                value: "\(workerPID)",
                isMonospaced: true
            ))
        }

        if let heartbeat = task.lastHeartbeatAt {
            fields.append(HermesInspectorField(
                id: "heartbeat",
                label: "Heartbeat",
                value: DateFormatters.shortDateTimeFormatter().string(from: Date(timeIntervalSince1970: TimeInterval(heartbeat)))
            ))
        }

        return fields
    }

    private func actionPanel(_ task: KanbanTask) -> some View {
        HermesSurfacePanel(
            title: "Update Task",
            subtitle: nil
        ) {
            VStack(alignment: .leading, spacing: 0) {
                if task.canSpecify {
                    KanbanActionDisclosureRow(
                        title: "Specify",
                        summary: "Promote this triage idea into a concrete todo",
                        systemImage: "sparkles.rectangle.stack",
                        isExpanded: expandedAction == .specify,
                        isDisabled: operationInFlight,
                        onToggle: { toggleAction(.specify) }
                    ) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.string("Hermes may refine the title and body before moving this task from Triage to Todo."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            Button(L10n.string("Specify Task")) {
                                Task {
                                    await onSpecify(task.id)
                                    expandedAction = nil
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(operationInFlight)
                        }
                    }

                    KanbanActionDivider()
                }

                KanbanActionDisclosureRow(
                    title: "Details",
                    summary: "Edit body, tenant, priority, and skills",
                    systemImage: "slider.horizontal.3",
                    isExpanded: expandedAction == .details,
                    isDisabled: operationInFlight,
                    onToggle: { toggleAction(.details) }
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        KanbanFormField(label: "Body") {
                            KanbanTextEditor(text: $draft.body, placeholder: L10n.string("Task description"))
                        }

                        HStack(alignment: .top, spacing: 12) {
                            KanbanFormField(label: "Tenant") {
                                TextField(L10n.string("optional"), text: $draft.tenant)
                                    .textFieldStyle(.roundedBorder)
                            }

                            KanbanFormField(label: "Priority") {
                                TextField("0", value: $draft.priority, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 96)
                            }
                        }

                        KanbanFormField(label: "Skills") {
                            TextField(L10n.string("deploy-check, release-notes"), text: $draft.skillsText)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(L10n.string("Apply")) {
                            Task {
                                await onUpdateFields(
                                    task.id,
                                    draft.normalizedBodyForUpdate,
                                    draft.normalizedTenantForUpdate,
                                    draft.priority,
                                    draft.skills
                                )
                                expandedAction = nil
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(operationInFlight || !detailsChanged(for: task))
                    }
                }

                KanbanActionDivider()

                if let detail {
                    KanbanActionDisclosureRow(
                        title: "Parents",
                        summary: dependencySummary(detail.parentIDs),
                        systemImage: "arrow.up.right.and.arrow.down.left.rectangle",
                        isExpanded: expandedAction == .parents,
                        isDisabled: operationInFlight,
                        onToggle: { toggleAction(.parents) }
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField(L10n.string("t_parent_a, t_parent_b"), text: $draft.parentIDsText)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))

                            Button(L10n.string("Apply")) {
                                Task {
                                    await onSetParents(task.id, draft.parentIDs)
                                    expandedAction = nil
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(operationInFlight || draft.parentIDs == detail.parentIDs)
                        }
                    }

                    KanbanActionDivider()

                    KanbanActionDisclosureRow(
                        title: "Children",
                        summary: dependencySummary(detail.childIDs),
                        systemImage: "point.3.connected.trianglepath.dotted",
                        isExpanded: expandedAction == .children,
                        isDisabled: operationInFlight,
                        onToggle: { toggleAction(.children) }
                    ) {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField(L10n.string("t_child_a, t_child_b"), text: $draft.childIDsText)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))

                            Button(L10n.string("Apply")) {
                                Task {
                                    await onSetChildren(task.id, draft.childIDs)
                                    expandedAction = nil
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(operationInFlight || draft.childIDs == detail.childIDs)
                        }
                    }

                    KanbanActionDivider()
                }

                KanbanActionDisclosureRow(
                    title: "Assignee",
                    summary: task.assignee.map { "@\($0)" } ?? "Unassigned",
                    systemImage: "person.crop.circle",
                    isExpanded: expandedAction == .assign,
                    isDisabled: operationInFlight,
                    onToggle: { toggleAction(.assign) }
                ) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            ComboBoxTextField(text: $draft.assignee, suggestions: assignees, placeholder: "unassigned")

                            Button(L10n.string("Apply")) {
                                Task {
                                    await onAssign(task.id, draft.normalizedAssignee)
                                    expandedAction = nil
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(operationInFlight || draft.normalizedAssignee == task.assignee)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            ComboBoxTextField(text: $draft.assignee, suggestions: assignees, placeholder: "unassigned")

                            Button(L10n.string("Apply")) {
                                Task {
                                    await onAssign(task.id, draft.normalizedAssignee)
                                    expandedAction = nil
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(operationInFlight || draft.normalizedAssignee == task.assignee)
                        }
                    }
                }

                KanbanActionDivider()

                KanbanActionDisclosureRow(
                    title: "Comment",
                    summary: "Add a note to the task history",
                    systemImage: "text.bubble",
                    isExpanded: expandedAction == .comment,
                    isDisabled: operationInFlight,
                    onToggle: { toggleAction(.comment) }
                ) {
                    VStack(alignment: .trailing, spacing: 8) {
                        KanbanTextEditor(text: $draft.comment, placeholder: L10n.string("Write a short update..."))

                        Button(L10n.string("Add Comment")) {
                            Task {
                                if await onComment(task.id, draft.comment) {
                                    draft.comment = ""
                                    expandedAction = nil
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(operationInFlight || draft.normalizedComment == nil)
                    }
                }

                if task.canComplete {
                    KanbanActionDivider()

                    KanbanActionDisclosureRow(
                        title: "Complete",
                        summary: "Finish the task with an optional handoff",
                        systemImage: "checkmark.circle",
                        isExpanded: expandedAction == .complete,
                        isDisabled: operationInFlight,
                        onToggle: { toggleAction(.complete) }
                    ) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                TextField(L10n.string("Optional handoff summary"), text: $draft.result)
                                    .textFieldStyle(.roundedBorder)

                                Button(L10n.string("Complete")) {
                                    Task {
                                        await onComplete(task.id, draft.normalizedResult)
                                        expandedAction = nil
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(operationInFlight)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                TextField(L10n.string("Optional handoff summary"), text: $draft.result)
                                    .textFieldStyle(.roundedBorder)

                                Button(L10n.string("Complete")) {
                                    Task {
                                        await onComplete(task.id, draft.normalizedResult)
                                        expandedAction = nil
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(operationInFlight)
                            }
                        }
                    }
                }

                if task.hasActiveWarnings || task.isRunning || task.status == .done {
                    KanbanActionDivider()

                    KanbanActionDisclosureRow(
                        title: "Recovery",
                        summary: recoverySummary(for: task),
                        systemImage: "wrench.and.screwdriver",
                        isExpanded: expandedAction == .recovery,
                        isDisabled: operationInFlight,
                        onToggle: { toggleAction(.recovery) }
                    ) {
                        VStack(alignment: .leading, spacing: 14) {
                            if let warnings = task.warnings, warnings.hasWarnings {
                                KanbanRecoveryWarningSummary(warnings: warnings)
                            }

                            if task.isRunning {
                                KanbanFormField(label: "Reason") {
                                    TextField(L10n.string("Optional recovery reason"), text: $draft.recoveryReason)
                                        .textFieldStyle(.roundedBorder)
                                }

                                Button(L10n.string("Reclaim Running Claim")) {
                                    Task {
                                        await onReclaim(task.id, draft.normalizedRecoveryReason)
                                        expandedAction = nil
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(operationInFlight)
                            }

                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 8) {
                                    ComboBoxTextField(text: $draft.assignee, suggestions: assignees, placeholder: "unassigned")

                                    Toggle(L10n.string("Reclaim first"), isOn: $draft.reclaimBeforeReassign)
                                        .toggleStyle(.checkbox)
                                        .disabled(!task.isRunning)

                                    Button(L10n.string("Reassign")) {
                                        Task {
                                            await onReassign(
                                                task.id,
                                                draft.normalizedAssignee,
                                                draft.reclaimBeforeReassign,
                                                draft.normalizedRecoveryReason
                                            )
                                            expandedAction = nil
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(operationInFlight || draft.normalizedAssignee == task.assignee)
                                }

                                VStack(alignment: .leading, spacing: 8) {
                                    ComboBoxTextField(text: $draft.assignee, suggestions: assignees, placeholder: "unassigned")

                                    Toggle(L10n.string("Reclaim first"), isOn: $draft.reclaimBeforeReassign)
                                        .toggleStyle(.checkbox)
                                        .disabled(!task.isRunning)

                                    Button(L10n.string("Reassign")) {
                                        Task {
                                            await onReassign(
                                                task.id,
                                                draft.normalizedAssignee,
                                                draft.reclaimBeforeReassign,
                                                draft.normalizedRecoveryReason
                                            )
                                            expandedAction = nil
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(operationInFlight || draft.normalizedAssignee == task.assignee)
                                }
                            }
                        }
                    }
                }

                if task.status == .done {
                    KanbanActionDivider()

                    KanbanActionDisclosureRow(
                        title: "Edit Result",
                        summary: "Backfill completion handoff and clear warnings",
                        systemImage: "square.and.pencil",
                        isExpanded: expandedAction == .editResult,
                        isDisabled: operationInFlight,
                        onToggle: { toggleAction(.editResult) }
                    ) {
                        VStack(alignment: .leading, spacing: 12) {
                            KanbanFormField(label: "Result") {
                                KanbanTextEditor(text: $draft.result, placeholder: L10n.string("Updated completion handoff"))
                            }

                            KanbanFormField(label: "Summary") {
                                TextField(L10n.string("Optional structured handoff summary"), text: $draft.recoverySummary)
                                    .textFieldStyle(.roundedBorder)
                            }

                            KanbanFormField(label: "Metadata JSON") {
                                TextField(L10n.string(#"Optional: {"changed_files":["README.md"]}"#), text: $draft.recoveryMetadata)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(.body, design: .monospaced))
                            }

                            Button(L10n.string("Save Result")) {
                                Task {
                                    await onEditResult(
                                        task.id,
                                        draft.normalizedResult ?? "",
                                        draft.normalizedRecoverySummary,
                                        draft.normalizedRecoveryMetadata
                                    )
                                    expandedAction = nil
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(operationInFlight || draft.normalizedResult == nil)
                        }
                    }
                }

                if task.canBlock {
                    KanbanActionDivider()

                    KanbanActionDisclosureRow(
                        title: "Block",
                        summary: "Pause the task and record the reason",
                        systemImage: "hand.raised",
                        isExpanded: expandedAction == .block,
                        isDisabled: operationInFlight,
                        onToggle: { toggleAction(.block) }
                    ) {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                TextField(L10n.string("Optional reason"), text: $draft.blockReason)
                                    .textFieldStyle(.roundedBorder)

                                Button(L10n.string("Block")) {
                                    Task {
                                        await onBlock(task.id, draft.normalizedBlockReason)
                                        expandedAction = nil
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(operationInFlight)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                TextField(L10n.string("Optional reason"), text: $draft.blockReason)
                                    .textFieldStyle(.roundedBorder)

                                Button(L10n.string("Block")) {
                                    Task {
                                        await onBlock(task.id, draft.normalizedBlockReason)
                                        expandedAction = nil
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(operationInFlight)
                            }
                        }
                    }
                }
            }
        }
    }

    private func detailsChanged(for task: KanbanTask) -> Bool {
        draft.normalizedBodyForUpdate != (task.trimmedBody ?? "") ||
            draft.normalizedTenantForUpdate != (task.tenant ?? "") ||
            draft.priority != task.priority ||
            draft.skills != task.skills
    }

    @ViewBuilder
    private func recoveryWarningPanel(_ task: KanbanTask) -> some View {
        if let warnings = task.warnings, warnings.hasWarnings {
            HermesSurfacePanel(
                title: warnings.displayTitle,
                subtitle: "Hermes Agent marked this task for recovery."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    KanbanRecoveryWarningSummary(warnings: warnings)

                    Text(L10n.string("Use Recovery to reclaim a stuck claim, retry with another assignee, or edit the final result after verifying the board state."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func recoverySummary(for task: KanbanTask) -> String {
        if task.hasActiveWarnings {
            return L10n.string("Review warnings and retry safely")
        }
        if task.isRunning {
            return L10n.string("Release or reassign a running worker")
        }
        return L10n.string("Edit a completed handoff")
    }

    private func dependencySummary(_ ids: [String]) -> String {
        if ids.isEmpty {
            return L10n.string("None")
        }
        if ids.count == 1 {
            return ids[0]
        }
        return L10n.string("%@ links", "\(ids.count)")
    }

    private func toggleAction(_ action: KanbanActionKind) {
        withAnimation(.snappy(duration: 0.16)) {
            expandedAction = expandedAction == action ? nil : action
        }
    }

    @ViewBuilder
    private func homeChannelsPanel(_ task: KanbanTask, _ taskDetail: KanbanTaskDetail) -> some View {
        if !taskDetail.homeChannels.isEmpty {
            HermesSurfacePanel(
                title: "Home Channels",
                subtitle: "Gateway home subscriptions for this task."
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(taskDetail.homeChannels, id: \.id) { homeChannel in
                        KanbanHomeChannelRow(
                            homeChannel: homeChannel,
                            isDisabled: operationInFlight,
                            onToggle: {
                                await onSetHomeSubscription(task.id, homeChannel, !homeChannel.subscribed)
                            }
                        )
                    }
                }
            }
        }
    }

    private func linksPanel(_ detail: KanbanTaskDetail) -> some View {
        HermesSurfacePanel(
            title: "Dependencies",
            subtitle: "Parent and child task links discovered on the board."
        ) {
            VStack(alignment: .leading, spacing: 12) {
                KanbanIDGroup(title: "Parents", ids: detail.parentIDs)
                KanbanIDGroup(title: "Children", ids: detail.childIDs)
            }
        }
    }

    private func commentsPanel(_ task: KanbanTask, _ detail: KanbanTaskDetail) -> some View {
        HermesSurfacePanel(
            title: "Comments",
            subtitle: "Human and agent notes attached to this task."
        ) {
            if detail.comments.isEmpty {
                Text(L10n.string("No comments yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(detail.comments) { comment in
                        KanbanCommentRow(comment: comment)
                    }
                }
            }
        }
    }

    private func runsPanel(_ detail: KanbanTaskDetail) -> some View {
        HermesSurfacePanel(
            title: "Runs",
            subtitle: "Attempt history recorded by Hermes."
        ) {
            if detail.runs.isEmpty {
                Text(L10n.string("No runs recorded yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(detail.runs) { run in
                        KanbanRunRow(run: run)
                    }
                }
            }
        }
    }

    private func eventsPanel(_ detail: KanbanTaskDetail) -> some View {
        HermesSurfacePanel(
            title: "Events",
            subtitle: "Chronological board events for this task."
        ) {
            if detail.events.isEmpty {
                Text(L10n.string("No events recorded yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(detail.events.suffix(20)) { event in
                        KanbanEventRow(event: event)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func logPanel(_ detail: KanbanTaskDetail) -> some View {
        if let log = detail.workerLog?.trimmingCharacters(in: .whitespacesAndNewlines), !log.isEmpty {
            HermesSurfacePanel(
                title: "Worker Log",
                subtitle: "Tail of the remote worker log for this task."
            ) {
                HermesInsetSurface {
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }
}
