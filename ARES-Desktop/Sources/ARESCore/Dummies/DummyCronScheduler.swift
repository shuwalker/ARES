import Foundation

/// In-memory cron scheduler for testing.
public final class DummyScheduler: Scheduler, @unchecked Sendable {
    private var _jobs: [String: ScheduledJob] = [:]

    public let capabilities: Set<String> = ["cronExpressions", "intervals"]

    public init() {
        print("🤖 [DUMMY] CronScheduler: initialized")
    }

    public func listJobs() async throws -> [ScheduledJob] {
        Array(_jobs.values)
    }

    public func getJob(_ id: String) async throws -> ScheduledJob {
        _jobs[id] ?? ScheduledJob(id: id, name: "unknown", expression: "", command: "")
    }

    public func schedule(name: String, expression: String, command: String, metadata: [String: AnyCodable]?) async throws -> ScheduledJob {
        let job = ScheduledJob(name: name, expression: expression, command: command, metadata: metadata ?? [:])
        _jobs[job.id] = job
        print("🤖 [DUMMY] CronScheduler schedule: \(name) '\(expression)'")
        return job
    }

    public func updateJob(_ id: String, name: String?, expression: String?, metadata: [String: AnyCodable]?) async throws -> ScheduledJob {
        print("🤖 [DUMMY] Scheduler update: \(id)")
        return _jobs[id] ?? ScheduledJob(id: id, name: name ?? "job", expression: expression ?? "", command: "")
    }

    public func pauseJob(_ id: String) async throws {
        if var job = _jobs[id] {
            job = ScheduledJob(id: job.id, name: job.name, expression: job.expression, command: job.command, isEnabled: false)
            _jobs[id] = job
            print("🤖 [DUMMY] Scheduler pause: \(id)")
        }
    }

    public func resumeJob(_ id: String) async throws {
        if var job = _jobs[id] {
            job = ScheduledJob(id: job.id, name: job.name, expression: job.expression, command: job.command, isEnabled: true)
            _jobs[id] = job
            print("🤖 [DUMMY] Scheduler resume: \(id)")
        }
    }

    public func deleteJob(_ id: String) async throws {
        _jobs.removeValue(forKey: id)
        print("🤖 [DUMMY] CronScheduler delete: \(id)")
    }

    public func triggerNow(_ id: String) async throws -> ScheduledExecution {
        print("🤖 [DUMMY] Scheduler trigger: \(id)")
        return ScheduledExecution(jobId: id, success: true, output: "ok")
    }

    public func history(_ jobId: String, limit: Int) async throws -> [ScheduledExecution] {
        print("🤖 [DUMMY] Scheduler history: \(jobId) (limit \(limit))")
        return []
    }
}
