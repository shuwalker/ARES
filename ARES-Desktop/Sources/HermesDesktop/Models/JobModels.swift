import Foundation

// MARK: - CronJob (Dashboard API)
// These models are used by the /api/claude-jobs Dashboard API endpoint.
// They are distinct from the SSH-based CronJob model in CronJobModels.swift.

struct DashboardCronJob: Identifiable, Codable, Sendable {
    let id: String
    var name: String
    var prompt: String
    var schedule: String
    var profile: String?
    var enabled: Bool
    var lastRun: String?
    var lastStatus: String?
    var nextRun: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case prompt
        case schedule
        case profile
        case enabled
        case lastRun = "last_run"
        case lastStatus = "last_status"
        case nextRun = "next_run"
    }
}

struct DashboardCronJobCreate: Encodable, Sendable {
    let name: String
    let prompt: String
    let schedule: String
    let profile: String?
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case prompt
        case schedule
        case profile
        case enabled
    }
}

struct DashboardCronJobPatch: Encodable, Sendable {
    let enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case enabled
    }
}
