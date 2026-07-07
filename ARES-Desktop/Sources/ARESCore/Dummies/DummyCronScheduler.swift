import Foundation

/// In-memory cron scheduler for testing.
public final class DummyScheduler: Scheduler, @unchecked Sendable {
    private let lock = NSLock()
    private var _jobs: [String: ScheduledJob] = [:]
    private var _history: [String: [ScheduledExecution]] = [:]

    public let capabilities: Set<String> = ["cronExpressions", "intervals"]

    public init() {
        print("🤖 [DUMMY] CronScheduler: initialized")
    }

    public func listJobs() async throws -> [ScheduledJob] {
        lock.withLock { Array(_jobs.values).sorted { $0.createdAt < $1.createdAt } }
    }

    public func getJob(_ id: String) async throws -> ScheduledJob {
        try lock.withLock {
            guard let job = _jobs[id] else {
                throw NSError(domain: "DummyScheduler", code: -1, userInfo: ["message": "Job not found"])
            }
            return job
        }
    }

    public func schedule(name: String, expression: String, command: String, metadata: [String: AnyCodable]?) async throws -> ScheduledJob {
        let job = ScheduledJob(
            name: name,
            expression: expression,
            command: command,
            nextRun: Self.estimatedNextRun(for: expression),
            metadata: metadata ?? [:]
        )
        lock.withLock {
            _jobs[job.id] = job
        }
        print("🤖 [DUMMY] CronScheduler schedule: \(name) '\(expression)'")
        return job
    }

    public func updateJob(_ id: String, name: String?, expression: String?, metadata: [String: AnyCodable]?) async throws -> ScheduledJob {
        print("🤖 [DUMMY] Scheduler update: \(id)")
        return try lock.withLock {
            guard let job = _jobs[id] else {
                throw NSError(domain: "DummyScheduler", code: -1, userInfo: ["message": "Job not found"])
            }
            let updatedExpression = expression ?? job.expression
            let updated = ScheduledJob(
                id: job.id,
                name: name ?? job.name,
                expression: updatedExpression,
                command: job.command,
                isEnabled: job.isEnabled,
                nextRun: Self.estimatedNextRun(for: updatedExpression),
                lastRun: job.lastRun,
                owner: job.owner,
                metadata: metadata ?? job.metadata,
                createdAt: job.createdAt,
                updatedAt: Date()
            )
            _jobs[id] = updated
            return updated
        }
    }

    public func pauseJob(_ id: String) async throws {
        try lock.withLock {
            guard let job = _jobs[id] else {
                throw NSError(domain: "DummyScheduler", code: -1, userInfo: ["message": "Job not found"])
            }
            _jobs[id] = job.withEnabled(false)
        }
        print("🤖 [DUMMY] Scheduler pause: \(id)")
    }

    public func resumeJob(_ id: String) async throws {
        try lock.withLock {
            guard let job = _jobs[id] else {
                throw NSError(domain: "DummyScheduler", code: -1, userInfo: ["message": "Job not found"])
            }
            _jobs[id] = job.withEnabled(true)
        }
        print("🤖 [DUMMY] Scheduler resume: \(id)")
    }

    public func deleteJob(_ id: String) async throws {
        lock.withLock {
            _jobs.removeValue(forKey: id)
            _history.removeValue(forKey: id)
        }
        print("🤖 [DUMMY] CronScheduler delete: \(id)")
    }

    public func triggerNow(_ id: String) async throws -> ScheduledExecution {
        print("🤖 [DUMMY] Scheduler trigger: \(id)")
        return try lock.withLock {
            guard let job = _jobs[id] else {
                throw NSError(domain: "DummyScheduler", code: -1, userInfo: ["message": "Job not found"])
            }
            let started = Date()
            let completed = Date()
            let execution = ScheduledExecution(
                jobId: id,
                startedAt: started,
                completedAt: completed,
                success: true,
                output: "alpha simulated run: \(job.command)",
                duration: completed.timeIntervalSince(started)
            )
            _history[id, default: []].append(execution)
            _jobs[id] = ScheduledJob(
                id: job.id,
                name: job.name,
                expression: job.expression,
                command: job.command,
                isEnabled: job.isEnabled,
                nextRun: Self.estimatedNextRun(for: job.expression),
                lastRun: completed,
                owner: job.owner,
                metadata: job.metadata,
                createdAt: job.createdAt,
                updatedAt: completed
            )
            return execution
        }
    }

    public func history(_ jobId: String, limit: Int) async throws -> [ScheduledExecution] {
        print("🤖 [DUMMY] Scheduler history: \(jobId) (limit \(limit))")
        return lock.withLock { Array(_history[jobId, default: []].suffix(max(0, limit))) }
    }

    private static func estimatedNextRun(for expression: String) -> Date? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("every ") {
            let interval = trimmed.dropFirst("every ".count)
            let value = Double(interval.dropLast()) ?? 1
            if interval.hasSuffix("s") { return Date().addingTimeInterval(value) }
            if interval.hasSuffix("m") { return Date().addingTimeInterval(value * 60) }
            if interval.hasSuffix("h") { return Date().addingTimeInterval(value * 3600) }
        }
        return Date().addingTimeInterval(3600)
    }
}

private extension ScheduledJob {
    func withEnabled(_ enabled: Bool) -> ScheduledJob {
        ScheduledJob(
            id: id,
            name: name,
            expression: expression,
            command: command,
            isEnabled: enabled,
            nextRun: enabled ? nextRun : nil,
            lastRun: lastRun,
            owner: owner,
            metadata: metadata,
            createdAt: createdAt,
            updatedAt: Date()
        )
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
