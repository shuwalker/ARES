import Foundation

/// A native macOS background task scheduler using Swift Concurrency.
/// Supports simple interval expressions like "every 5s" or "every 1m".
public actor NativeMacScheduler: Scheduler {
    private var jobs: [String: ScheduledJob] = [:]
    private var history: [String: [ScheduledExecution]] = [:]
    private var activeTasks: [String: Task<Void, Never>] = [:]

    public let capabilities: Set<String> = ["intervals"]

    public init() {
        print("✅ [WIRING] NativeMacScheduler: initialized")
    }

    public func listJobs() async throws -> [ScheduledJob] {
        return Array(jobs.values).sorted { $0.createdAt < $1.createdAt }
    }

    public func getJob(_ id: String) async throws -> ScheduledJob {
        guard let job = jobs[id] else {
            throw NSError(domain: "NativeMacScheduler", code: 404, userInfo: ["message": "Job not found"])
        }
        return job
    }

    public func schedule(name: String, expression: String, command: String, metadata: [String: AnyCodable]?) async throws -> ScheduledJob {
        let job = ScheduledJob(
            name: name,
            expression: expression,
            command: command,
            nextRun: estimatedNextRun(for: expression),
            metadata: metadata ?? [:]
        )
        jobs[job.id] = job
        startJobLoop(for: job)
        print("🕒 [SCHEDULER] Scheduled: \(name) '\(expression)'")
        return job
    }

    public func updateJob(_ id: String, name: String?, expression: String?, metadata: [String: AnyCodable]?) async throws -> ScheduledJob {
        guard let job = jobs[id] else {
            throw NSError(domain: "NativeMacScheduler", code: 404, userInfo: ["message": "Job not found"])
        }
        let updatedExpression = expression ?? job.expression
        let updated = ScheduledJob(
            id: job.id,
            name: name ?? job.name,
            expression: updatedExpression,
            command: job.command,
            isEnabled: job.isEnabled,
            nextRun: estimatedNextRun(for: updatedExpression),
            lastRun: job.lastRun,
            owner: job.owner,
            metadata: metadata ?? job.metadata,
            createdAt: job.createdAt,
            updatedAt: Date()
        )
        jobs[id] = updated
        
        if updated.isEnabled {
            startJobLoop(for: updated)
        }
        
        print("🕒 [SCHEDULER] Updated: \(id)")
        return updated
    }

    public func pauseJob(_ id: String) async throws {
        guard let job = jobs[id] else {
            throw NSError(domain: "NativeMacScheduler", code: 404, userInfo: ["message": "Job not found"])
        }
        jobs[id] = job.withEnabled(false)
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
        print("⏸️ [SCHEDULER] Paused: \(id)")
    }

    public func resumeJob(_ id: String) async throws {
        guard let job = jobs[id] else {
            throw NSError(domain: "NativeMacScheduler", code: 404, userInfo: ["message": "Job not found"])
        }
        let resumed = job.withEnabled(true)
        jobs[id] = resumed
        startJobLoop(for: resumed)
        print("▶️ [SCHEDULER] Resumed: \(id)")
    }

    public func deleteJob(_ id: String) async throws {
        jobs.removeValue(forKey: id)
        history.removeValue(forKey: id)
        activeTasks[id]?.cancel()
        activeTasks.removeValue(forKey: id)
        print("🗑️ [SCHEDULER] Deleted: \(id)")
    }

    public func triggerNow(_ id: String) async throws -> ScheduledExecution {
        guard let job = jobs[id] else {
            throw NSError(domain: "NativeMacScheduler", code: 404, userInfo: ["message": "Job not found"])
        }
        return try await executeJob(job)
    }

    public func history(_ jobId: String, limit: Int) async throws -> [ScheduledExecution] {
        return Array(history[jobId, default: []].suffix(max(0, limit)))
    }

    // MARK: - Execution Loop

    private func startJobLoop(for job: ScheduledJob) {
        // Cancel existing loop
        activeTasks[job.id]?.cancel()

        guard job.isEnabled else { return }

        let interval = parseInterval(from: job.expression)
        guard interval > 0 else {
            print("⚠️ [SCHEDULER] Invalid interval for job \(job.id)")
            return
        }

        let task = Task {
            while !Task.isCancelled {
                // Sleep for the interval
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    
                    if Task.isCancelled { break }
                    
                    // Fire the job
                    _ = try await self.executeJob(job)
                    
                } catch is CancellationError {
                    break
                } catch {
                    print("⚠️ [SCHEDULER] Sleep error: \(error)")
                }
            }
        }
        activeTasks[job.id] = task
    }

    private func executeJob(_ job: ScheduledJob) async throws -> ScheduledExecution {
        print("⚡️ [SCHEDULER] Executing: \(job.name)")
        let started = Date()
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", job.command]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        
        var outputStr = ""
        var success = false
        
        do {
            try process.run()
            process.waitUntilExit()
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            outputStr = String(data: data, encoding: .utf8) ?? ""
            success = process.terminationStatus == 0
        } catch {
            outputStr = error.localizedDescription
        }

        let completed = Date()
        let execution = ScheduledExecution(
            jobId: job.id,
            startedAt: started,
            completedAt: completed,
            success: success,
            output: outputStr,
            duration: completed.timeIntervalSince(started)
        )
        
        history[job.id, default: []].append(execution)
        
        // Update job last run time
        if let current = jobs[job.id] {
            jobs[job.id] = ScheduledJob(
                id: current.id,
                name: current.name,
                expression: current.expression,
                command: current.command,
                isEnabled: current.isEnabled,
                nextRun: estimatedNextRun(for: current.expression),
                lastRun: completed,
                owner: current.owner,
                metadata: current.metadata,
                createdAt: current.createdAt,
                updatedAt: completed
            )
        }
        
        return execution
    }

    // MARK: - Helpers

    private func parseInterval(from expression: String) -> TimeInterval {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("every ") {
            let intervalStr = trimmed.dropFirst("every ".count)
            let value = Double(intervalStr.dropLast()) ?? 1
            if intervalStr.hasSuffix("s") { return value }
            if intervalStr.hasSuffix("m") { return value * 60 }
            if intervalStr.hasSuffix("h") { return value * 3600 }
        }
        return 0
    }

    private func estimatedNextRun(for expression: String) -> Date? {
        let interval = parseInterval(from: expression)
        return interval > 0 ? Date().addingTimeInterval(interval) : nil
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
