import Foundation

/// Scheduler protocol: recurring task execution and management.
/// Bridges cron-like scheduling to reasoning (agent can schedule itself).
/// Conforming types: LaunchctlScheduler, HermesScheduler, DummyScheduler
public protocol Scheduler: AnyObject, Sendable {
    /// List all scheduled jobs.
    func listJobs() async throws -> [ScheduledJob]

    /// Get a specific job by ID.
    func getJob(_ id: String) async throws -> ScheduledJob

    /// Schedule a new recurring task.
    /// Cron expression (5-part: minute hour day month weekday) or interval.
    func schedule(
        name: String,
        expression: String,                    // "0 9 * * 1" or "every 5m"
        command: String,
        metadata: [String: AnyCodable]?
    ) async throws -> ScheduledJob

    /// Update a job (name, expression, metadata only; not command).
    func updateJob(_ id: String, name: String?, expression: String?, metadata: [String: AnyCodable]?) async throws -> ScheduledJob

    /// Pause a job (don't delete, just disable).
    func pauseJob(_ id: String) async throws

    /// Resume a paused job.
    func resumeJob(_ id: String) async throws

    /// Delete a job.
    func deleteJob(_ id: String) async throws

    /// Manually trigger a job immediately.
    func triggerNow(_ id: String) async throws -> ScheduledExecution

    /// Get execution history for a job.
    func history(_ jobId: String, limit: Int) async throws -> [ScheduledExecution]

    /// What can this scheduler do?
    /// Examples: ["cronExpressions", "intervals", "retries", "notifications"]
    var capabilities: Set<String> { get }
}

/// A scheduled job (generic, not just cron).
public struct ScheduledJob: Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let expression: String              // "0 9 * * 1" or "every 5m"
    public let command: String                 // What to run (shell, skill, agent task, etc.)
    public let isEnabled: Bool
    public let nextRun: Date?
    public let lastRun: Date?
    public let owner: String?                  // Who created/owns this job
    public let metadata: [String: AnyCodable]
    public let createdAt: Date
    public let updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        expression: String,
        command: String,
        isEnabled: Bool = true,
        nextRun: Date? = nil,
        lastRun: Date? = nil,
        owner: String? = nil,
        metadata: [String: AnyCodable] = [:],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.expression = expression
        self.command = command
        self.isEnabled = isEnabled
        self.nextRun = nextRun
        self.lastRun = lastRun
        self.owner = owner
        self.metadata = metadata
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A single execution of a scheduled job.
public struct ScheduledExecution: Codable, Sendable, Equatable {
    public let id: String
    public let jobId: String
    public let startedAt: Date
    public let completedAt: Date?
    public let success: Bool?                  // nil = still running
    public let output: String?
    public let error: String?
    public let duration: TimeInterval?

    public init(
        id: String = UUID().uuidString,
        jobId: String,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        success: Bool? = nil,
        output: String? = nil,
        error: String? = nil,
        duration: TimeInterval? = nil
    ) {
        self.id = id
        self.jobId = jobId
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.success = success
        self.output = output
        self.error = error
        self.duration = duration
    }
}
