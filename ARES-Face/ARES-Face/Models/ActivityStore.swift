import Foundation
import Combine

/// Entity-framed self-improvement timeline.
///
/// Not a log file. This is "what ARES is doing, what it learned, what happened."
/// Inspired by Hermes Desktop's self-improvement timeline, but entity-framed:
/// instead of "cron job #4 ran", it says "ARES checked the NAS and found 3 new files."
///
/// Events come from:
///   - HermesDashboardService (cron results, session state, skill changes)
///   - BrainConnection (chat events, cognitive changes)
///   - FeedStore (alert triggers)
@MainActor
final class ActivityStore: ObservableObject {
    @Published var events: [ActivityEvent] = []
    @Published var activeGoals: [ActivityGoal] = []
    @Published var isLoading = false

    private let dashboard: HermesDashboardService

    init(dashboard: HermesDashboardService = HermesDashboardService()) {
        self.dashboard = dashboard
    }

    // MARK: - Fetch

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        // Pull cron execution history from Hermes dashboard API
        if let crons = try? await dashboard.listCronJobs() {
            for job in crons {
                // Convert cron results into activity events
                if let lastRunTs = job.lastRunAt, lastRunTs > 0 {
                    let lastRun = Date(timeIntervalSince1970: lastRunTs)
                    let event = ActivityEvent(
                        kind: .cronCompleted,
                        title: job.name ?? job.id,
                        detail: "Ran on schedule — \(job.schedule ?? "unknown")",
                        timestamp: lastRun,
                        status: job.lastStatus == "success" ? .success : .failure
                    )
                    if !events.contains(where: { $0.id == event.id }) {
                        events.append(event)
                    }
                }
            }
        }

        // Sort newest first
        events.sort { $0.timestamp > $1.timestamp }

        // Keep last 200 events (don't grow unbounded)
        if events.count > 200 {
            events = Array(events.prefix(200))
        }
    }

    // MARK: - Push (called by BrainConnection, FeedStore, etc.)

    func push(_ event: ActivityEvent) {
        events.insert(event, at: 0)
        if events.count > 200 {
            events = Array(events.prefix(200))
        }
    }

    func push(kind: ActivityEvent.Kind, title: String, detail: String) {
        push(ActivityEvent(kind: kind, title: title, detail: detail))
    }

    // MARK: - Goals

    func addGoal(_ goal: ActivityGoal) {
        activeGoals.append(goal)
    }

    func completeGoal(id: String) {
        activeGoals.removeAll { $0.id == id }
    }
}

// MARK: - Models

struct ActivityEvent: Identifiable, Equatable {
    let id: String
    let kind: Kind
    let title: String
    let detail: String
    let timestamp: Date
    let status: Status

    init(kind: Kind, title: String, detail: String,
         timestamp: Date = .now, status: Status = .success) {
        self.id = "\(kind.rawValue)-\(Int(timestamp.timeIntervalSince1970))-\(title.hashValue)"
        self.kind = kind
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
        self.status = status
    }

    enum Kind: String, CaseIterable {
        case cronCompleted = "cron"
        case skillWritten = "skill"
        case memoryChange = "memory"
        case goalProgress = "goal"
        case feedAlert = "alert"
        case sessionEvent = "session"
        case selfImprovement = "learned"
    }

    enum Status: String {
        case success
        case failure
        case inProgress
    }
}

struct ActivityGoal: Identifiable {
    let id = UUID().uuidString
    var description: String
    var completionCondition: String
    var createdAt: Date = .now
    var isCompleted = false
}