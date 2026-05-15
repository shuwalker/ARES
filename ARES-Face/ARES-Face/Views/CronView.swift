import SwiftUI

/// Cron job browser — list, pause, resume, delete, run from Hermes dashboard API.
/// Hermes-inspired styling with status badges and action buttons.
struct CronView: View {
    @State private var jobs: [CronJob] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            toolbar

            Divider()
                .background(ARESPalette.surfaceBorder)

            if isLoading {
                loadingState
            } else if let error = errorMessage {
                errorState(error)
            } else {
                jobList
            }
        }
        .onAppear { loadJobs() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text("Cron Jobs")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)

            Spacer()

            Text("\(jobs.count) jobs")
                .font(.system(size: 11))
                .foregroundStyle(.secondary.opacity(0.6))

            if !isLoading {
                Button {
                    loadJobs()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                        Text("Refresh")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(.primary)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.15))
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack {
            Spacer()
            ProgressView("Loading cron jobs...")
                .controlSize(.small)
            Spacer()
        }
    }

    // MARK: - Error

    private func errorState(_ error: String) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Button("Retry") { loadJobs() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
            Spacer()
        }
    }

    // MARK: - Job List

    private var jobList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(jobs) { job in
                    CronJobListRow(job: job) { action in
                        performAction(action, jobID: job.id)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Data

    private func loadJobs() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                jobs = try await HermesDashboardService.shared.listCronJobs()
                isLoading = false
            } catch {
                errorMessage = error.localizedDescription
                isLoading = false
            }
        }
    }

    private func performAction(_ action: CronAction, jobID: String) {
        Task {
            do {
                let svc = HermesDashboardService.shared
                switch action {
                case .pause: try await svc.pauseCronJob(jobID)
                case .resume: try await svc.resumeCronJob(jobID)
                case .delete: try await svc.deleteCronJob(jobID)
                case .run: try await svc.runCronJob(jobID)
                }
                loadJobs()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

enum CronAction {
    case pause, resume, delete, run
}

// MARK: - CronJob List Row

struct CronJobListRow: View {
    let job: CronJob
    let onAction: (CronAction) -> Void
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Status dot
            statusCircle

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(job.name ?? job.id.prefix(12).description)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.9))
                        .lineLimit(1)

                    statusBadge
                }

                HStack(spacing: 10) {
                    if let sched = job.schedule {
                        metaLabel(sched, icon: "calendar")
                    }
                    if let last = job.lastStatus {
                        metaLabel(last, icon: "checkmark.circle")
                    }
                    if let error = job.lastError {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundStyle(.red.opacity(0.8))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Actions
            HStack(spacing: 6) {
                if job.state == "paused" || job.state == "error" {
                    actionButton("play.fill", .resume, color: .green)
                } else {
                    actionButton("pause.fill", .pause, color: .orange)
                }
                actionButton("forward.fill", .run, color: .cyan)
                actionButton("trash", .delete, color: .red.opacity(0.8))
            }
            .opacity(isHovered ? 1.0 : 0.4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? Color.white.opacity(0.04) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isHovered ? ARESPalette.surfaceBorder : Color.clear, lineWidth: 0.5)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var statusCircle: some View {
        Circle()
            .fill(stateColor)
            .frame(width: 8, height: 8)
            .shadow(color: stateColor.opacity(0.3), radius: 3)
    }

    private var stateColor: Color {
        switch job.state {
        case "running": return .green
        case "paused": return .orange
        case "error", "failed": return .red
        default: return .gray.opacity(0.4)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if let state = job.state {
            Text(state)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(stateColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(stateColor.opacity(0.12))
                )
        }
    }

    private func metaLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 10))
        }
        .foregroundStyle(.secondary.opacity(0.6))
    }

    private func actionButton(_ icon: String, _ action: CronAction, color: Color) -> some View {
        Button {
            onAction(action)
        } label: {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(color.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
    }
}
