import SwiftUI

// MARK: - Schedule Presets

private enum JobSchedulePreset: String, CaseIterable, Identifiable {
    case everyHour = "Every hour"
    case everyDay9am = "Every day 9am"
    case everyMonday = "Every Monday"
    case custom = "Custom"

    var id: String { rawValue }

    var expression: String? {
        switch self {
        case .everyHour: return "0 * * * *"
        case .everyDay9am: return "0 9 * * *"
        case .everyMonday: return "0 9 * * 1"
        case .custom: return nil
        }
    }
}

// MARK: - JobsView

struct JobsView: View {
    @EnvironmentObject private var appState: AppState

    @State private var showCreateSheet = false
    @State private var jobToDelete: DashboardCronJob?

    var body: some View {
        HermesPageContainer(width: .dashboard) {
            VStack(alignment: .leading, spacing: 24) {
                header

                if !appState.dashboardAPIAvailable {
                    unavailableView
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task(id: appState.activeConnectionID) {
            guard appState.dashboardAPIAvailable else { return }
            await appState.loadDashboardCronJobs()
        }
        .sheet(isPresented: $showCreateSheet) {
            CreateJobSheet { job in
                Task {
                    await appState.createDashboardCronJob(job)
                }
            }
        }
        .alert(L10n.string("Delete job?"), isPresented: .constant(jobToDelete != nil)) {
            Button(L10n.string("Delete"), role: .destructive) {
                if let job = jobToDelete {
                    Task {
                        await appState.deleteDashboardCronJob(id: job.id)
                    }
                }
                jobToDelete = nil
            }
            Button(L10n.string("Cancel"), role: .cancel) {
                jobToDelete = nil
            }
        } message: {
            if let job = jobToDelete {
                Text(L10n.string(""%@" will be permanently deleted.", job.name))
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HermesPageHeader(
            title: "Jobs",
            subtitle: "Schedule recurring Claude jobs using cron expressions."
        ) {
            HStack(spacing: 10) {
                HermesRefreshButton(isRefreshing: appState.isLoadingDashboardCronJobs) {
                    Task { await appState.loadDashboardCronJobs() }
                }

                Button {
                    showCreateSheet = true
                } label: {
                    Label(L10n.string("New Job"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(!appState.dashboardAPIAvailable)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    // MARK: - Unavailable

    private var unavailableView: some View {
        HermesSurfacePanel {
            ContentUnavailableView(
                L10n.string("Dashboard API Unavailable"),
                systemImage: "clock.badge.checkmark",
                description: Text(L10n.string("Jobs management requires a local Hermes connection or an active SSH tunnel."))
            )
            .frame(maxWidth: .infinity, minHeight: 300)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if appState.isLoadingDashboardCronJobs && appState.dashboardCronJobs.isEmpty {
            HermesSurfacePanel {
                HermesLoadingState(label: "Loading jobs…", minHeight: 300)
            }
        } else if let error = appState.dashboardCronJobsError, appState.dashboardCronJobs.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("Unable to load jobs"),
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else if appState.dashboardCronJobs.isEmpty {
            HermesSurfacePanel {
                ContentUnavailableView(
                    L10n.string("No Jobs"),
                    systemImage: "clock.badge.checkmark",
                    description: Text(L10n.string("Create a new job to get started."))
                )
                .frame(maxWidth: .infinity, minHeight: 300)
            }
        } else {
            jobsListPanel
        }
    }

    private var jobsListPanel: some View {
        HermesSurfacePanel(
            title: "Scheduled Jobs",
            subtitle: "\(appState.dashboardCronJobs.count) job(s) configured."
        ) {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(appState.dashboardCronJobs) { job in
                    JobRowCard(
                        job: job,
                        onToggle: { enabled in
                            Task { await appState.toggleDashboardCronJob(id: job.id, enabled: enabled) }
                        },
                        onDelete: {
                            jobToDelete = job
                        }
                    )
                }
            }
        }
    }
}

// MARK: - Job Row Card

private struct JobRowCard: View {
    let job: DashboardCronJob
    let onToggle: (Bool) -> Void
    let onDelete: () -> Void

    private var humanSchedule: String {
        CronScheduleFormatter.humanReadableDescription(for: job.schedule) ?? job.schedule
    }

    private var lastStatusColor: Color {
        switch job.lastStatus {
        case "success": return .green
        case "failure": return .red
        default: return .secondary
        }
    }

    private var lastStatusIcon: String {
        switch job.lastStatus {
        case "success": return "checkmark.circle.fill"
        case "failure": return "xmark.circle.fill"
        default: return "minus.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(job.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if let profile = job.profile, !profile.isEmpty {
                            HermesBadge(text: profile, tint: .blue)
                        }
                    }

                    HStack(spacing: 10) {
                        Label(humanSchedule, systemImage: "clock")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let nextRun = job.nextRun, !nextRun.isEmpty {
                            Text(L10n.string("Next: %@", nextRun))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let lastRun = job.lastRun, !lastRun.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: lastStatusIcon)
                                .font(.caption)
                                .foregroundStyle(lastStatusColor)
                            Text(L10n.string("Last run: %@", lastRun))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { job.enabled },
                        set: { onToggle($0) }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help(job.enabled ? L10n.string("Disable job") : L10n.string("Enable job"))

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                    .help(L10n.string("Delete job"))
                }
            }

            if !job.prompt.isEmpty {
                Text(job.prompt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .fill(HermesTheme.rowFill)
        )
        .overlay {
            RoundedRectangle(cornerRadius: HermesTheme.rowCornerRadius, style: .continuous)
                .strokeBorder(HermesTheme.subtleStroke, lineWidth: 1)
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(L10n.string("Delete"), systemImage: "trash")
            }
        }
    }
}

// MARK: - Create Job Sheet

struct CreateJobSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    let onCreate: (DashboardCronJobCreate) -> Void

    @State private var name = ""
    @State private var prompt = ""
    @State private var schedulePreset: JobSchedulePreset = .everyDay9am
    @State private var customSchedule = ""
    @State private var selectedProfile = ""

    private var resolvedSchedule: String {
        if schedulePreset == .custom {
            return customSchedule.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return schedulePreset.expression ?? ""
    }

    private var availableProfiles: [String] {
        guard let overview = appState.overview else { return [] }
        return overview.availableProfiles.map { $0.name }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !resolvedSchedule.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(L10n.string("New Job"))
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 14) {
                labeledField(title: "Name") {
                    TextField(L10n.string("Job name…"), text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                labeledField(title: "Prompt") {
                    TextEditor(text: $prompt)
                        .font(.body)
                        .frame(minHeight: 80, maxHeight: 160)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }

                labeledField(title: "Schedule") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker(L10n.string("Schedule"), selection: $schedulePreset) {
                            ForEach(JobSchedulePreset.allCases) { preset in
                                Text(L10n.string(preset.rawValue)).tag(preset)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 260)

                        if schedulePreset == .custom {
                            TextField(L10n.string("Cron expression e.g. 0 9 * * *"), text: $customSchedule)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                        } else if let expr = schedulePreset.expression {
                            Text(expr)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if !availableProfiles.isEmpty {
                    labeledField(title: "Profile") {
                        Picker(L10n.string("Profile"), selection: $selectedProfile) {
                            Text(L10n.string("Default")).tag("")
                            ForEach(availableProfiles, id: \.self) { profile in
                                Text(profile).tag(profile)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(maxWidth: 260)
                    }
                }
            }

            HStack {
                Spacer()

                Button(L10n.string("Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(L10n.string("Create Job")) {
                    let job = DashboardCronJobCreate(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                        schedule: resolvedSchedule,
                        profile: selectedProfile.isEmpty ? nil : selectedProfile,
                        enabled: true
                    )
                    onCreate(job)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private func labeledField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(title))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
