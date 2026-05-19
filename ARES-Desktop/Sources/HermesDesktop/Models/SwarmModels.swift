import Foundation

// MARK: - Worker

struct SwarmWorker: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let role: String
    var status: String          // "active" | "idle" | "offline"
    var currentMission: String?
    var tokenCount: Int?
    var sessionId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case role
        case status
        case currentMission = "current_mission"
        case tokenCount = "token_count"
        case sessionId = "session_id"
    }
}

// MARK: - Mission

struct SwarmMission: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let worker: String
    var status: String          // "running" | "review" | "done" | "blocked"
    var progress: Double?
    var createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case worker
        case status
        case progress
        case createdAt = "created_at"
    }
}

// MARK: - Health

struct SwarmHealth: Codable, Sendable {
    let workersOnline: Int
    let workersTotal: Int
    let missionsRunning: Int
    let systemLoad: Double?

    enum CodingKeys: String, CodingKey {
        case workersOnline = "workers_online"
        case workersTotal = "workers_total"
        case missionsRunning = "missions_running"
        case systemLoad = "system_load"
    }
}

// MARK: - Kanban Card

struct SwarmKanbanCard: Identifiable, Codable, Sendable {
    let id: String
    var title: String
    var column: String          // "backlog" | "ready" | "running" | "review" | "blocked" | "done"
    var worker: String?
    var priority: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case column
        case worker
        case priority
    }
}

// MARK: - Runtime

struct SwarmRuntimeWorker: Codable, Sendable {
    let workerId: String?
    let sessionOutput: String?
    let pid: Int?
    let uptime: String?

    enum CodingKeys: String, CodingKey {
        case workerId = "worker_id"
        case sessionOutput = "session_output"
        case pid
        case uptime
    }
}

struct SwarmRuntime: Codable, Sendable {
    let workers: [SwarmRuntimeWorker]?
}

// MARK: - Report

struct SwarmReport: Identifiable, Codable, Sendable {
    let id: String
    let missionTitle: String
    let worker: String
    let status: String          // "needs_review" | "ready_to_merge" | "done" | "blocked"
    let summary: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case missionTitle = "mission_title"
        case worker
        case status
        case summary
        case createdAt = "created_at"
    }
}

// MARK: - Memory File

struct SwarmMemoryFile: Identifiable, Codable, Sendable {
    let id: String
    let worker: String
    let filename: String
    let content: String?

    enum CodingKeys: String, CodingKey {
        case id
        case worker
        case filename
        case content
    }
}

// MARK: - Dispatch Request

struct SwarmDispatchRequest: Codable, Sendable {
    let worker: String
    let prompt: String
    let missionId: String?

    enum CodingKeys: String, CodingKey {
        case worker
        case prompt
        case missionId = "mission_id"
    }
}

// MARK: - Chat Request

struct SwarmDirectChatRequest: Codable, Sendable {
    let worker: String
    let message: String
}

// MARK: - Lifecycle Request

struct SwarmLifecycleRequest: Codable, Sendable {
    let action: String          // "auto-sweep" | "request-handoff" | "renew"
    let worker: String?
}

// MARK: - Conductor

struct ConductorWorkerCard: Identifiable, Sendable {
    let id: String
    let workerName: String
    var status: String          // "Idle" | "Thinking" | "Running" | "Done"
    var tokenCount: Int
    var startTime: Date?
    var output: String
}

// MARK: - Operations

struct OperationsAgent: Identifiable, Codable, Sendable {
    let id: String
    var name: String
    var role: String?
    var profile: String?
}

// MARK: - Crew Status

struct CrewStatusEntry: Identifiable, Sendable {
    let id: String              // profile name
    let profileName: String
    var isOnline: Bool
    var sessionCount: Int
    var messageCount: Int
    var tokenCount: Int
    var estimatedCost: Double
    var cronJobCount: Int
}
