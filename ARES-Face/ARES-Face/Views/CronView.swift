import SwiftUI

/// Cron job browser — list, pause, resume, delete, run from Hermes dashboard API.
/// From OS1 pattern: action buttons per row, last status, schedule display.
struct CronView: View {
    @State private var jobs: [CronJob] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Cron Jobs").font(.headline)
                Spacer()
                if !isLoading {
                    Button("Refresh") { loadJobs() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            .padding(10)
            .background(.ultraThinMaterial)
            
            if isLoading {
                Spacer()
                ProgressView("Loading cron jobs...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                    Text(error).font(.caption).foregroundStyle(.secondary)
                    Button("Retry") { loadJobs() }.buttonStyle(.bordered)
                }
                Spacer()
            } else if jobs.isEmpty {
                Spacer()
                Text("No cron jobs scheduled")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                List(jobs) { job in
                    CronJobRow(job: job, onAction: { action in
                        performAction(action, jobID: job.id)
                    })
                }
                .listStyle(.inset)
            }
        }
        .onAppear { loadJobs() }
    }
    
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

struct CronJobRow: View {
    let job: CronJob
    let onAction: (CronAction) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Status dot
            Circle()
                .fill(job.state == "running" ? Color.green :
                      job.state == "paused" ? Color.orange :
                      job.state == "error" || job.state == "failed" ? Color.red :
                      Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(job.name ?? job.id.prefix(12).description)
                    .font(.body.weight(.medium))
                HStack(spacing: 8) {
                    if let sched = job.schedule {
                        Text(sched).font(.caption).foregroundStyle(.teal)
                    }
                    if let state = job.state {
                        Text(state).font(.caption).foregroundStyle(.secondary)
                    }
                    if let last = job.lastStatus {
                        Text(last).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error = job.lastError {
                    Text(error).font(.caption2).foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 4) {
                if job.state == "paused" || job.state == "error" {
                    Button { onAction(.resume) } label: {
                        Image(systemName: "play.fill").font(.caption)
                    }.buttonStyle(.plain).help("Resume")
                } else {
                    Button { onAction(.pause) } label: {
                        Image(systemName: "pause.fill").font(.caption)
                    }.buttonStyle(.plain).help("Pause")
                }
                Button { onAction(.run) } label: {
                    Image(systemName: "forward.fill").font(.caption)
                }.buttonStyle(.plain).help("Run now")
                Button { onAction(.delete) } label: {
                    Image(systemName: "trash").font(.caption)
                        .foregroundStyle(.red)
                }.buttonStyle(.plain).help("Delete")
            }
        }
        .padding(.vertical, 4)
    }
}