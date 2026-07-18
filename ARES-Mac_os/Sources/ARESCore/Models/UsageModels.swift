import Foundation

public struct UsageSummary: Codable {
    public let ok: Bool
    public let state: UsageSummaryState
    public let sessionCount: Int
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let cacheReadTokens: Int64
    public let cacheWriteTokens: Int64
    public let reasoningTokens: Int64
    public let topSessions: [UsageTopSession]
    public let topModels: [UsageTopModel]
    public let recentSessions: [UsageRecentSession]
    public let databasePath: String?
    public let sessionTable: String?
    public let message: String?
    public let missingColumns: [String]

    enum CodingKeys: String, CodingKey {
        case ok
        case state
        case sessionCount = "session_count"
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case cacheWriteTokens = "cache_write_tokens"
        case reasoningTokens = "reasoning_tokens"
        case topSessions = "top_sessions"
        case topModels = "top_models"
        case recentSessions = "recent_sessions"
        case databasePath = "database_path"
        case sessionTable = "session_table"
        case message
        case missingColumns = "missing_columns"
    }
}

public struct UsageSessionMetric: Codable, Identifiable, Hashable, TitleIdentifiable {
    public let id: String
    public let title: String?
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let totalTokens: Int64

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
    }
}

public typealias UsageRecentSession = UsageSessionMetric
public typealias UsageTopSession = UsageSessionMetric

public struct UsageTopModel: Codable, Identifiable, Hashable {
    public let model: String
    public let billingProvider: String?
    public let sessionCount: Int
    public let totalTokens: Int64
    public let cacheAndReasoningTokens: Int64
    public let estimatedCostUSD: Double

    public var id: String { model }

    enum CodingKeys: String, CodingKey {
        case model
        case billingProvider = "billing_provider"
        case sessionCount = "session_count"
        case totalTokens = "total_tokens"
        case cacheAndReasoningTokens = "cache_reasoning_tokens"
        case estimatedCostUSD = "estimated_cost_usd"
    }
}

public enum UsageSummaryState: String, Codable {
    case available
    case unavailable
}

public struct UsageProfileBreakdown: Hashable {
    public let profiles: [UsageProfileSlice]

    public init(profiles: [UsageProfileSlice]) {
        self.profiles = profiles
    }

    public var readableProfiles: [UsageProfileSlice] {
        profiles.filter { $0.state == .available }
    }

    public var chartProfiles: [UsageProfileSlice] {
        readableProfiles.filter { $0.allTokenCategoriesTotal > 0 }
    }

    public var hostWideAllTokenCategoriesTotal: Int64 {
        readableProfiles.reduce(into: 0) { partialResult, profile in
            partialResult += profile.allTokenCategoriesTotal
        }
    }

    public var unavailableProfiles: [UsageProfileSlice] {
        profiles.filter { $0.state == .unavailable }
    }
}

public struct UsageProfileSlice: Identifiable, Hashable {
    public init(profileName: String, hermesHomePath: String, state: ARESCore.UsageSummaryState, sessionCount: Int, inputTokens: Int64, outputTokens: Int64, cacheReadTokens: Int64, cacheWriteTokens: Int64, reasoningTokens: Int64, databasePath: String?, message: String?, isActiveProfile: Bool) { self.profileName = profileName; self.hermesHomePath = hermesHomePath; self.state = state; self.sessionCount = sessionCount; self.inputTokens = inputTokens; self.outputTokens = outputTokens; self.cacheReadTokens = cacheReadTokens; self.cacheWriteTokens = cacheWriteTokens; self.reasoningTokens = reasoningTokens; self.databasePath = databasePath; self.message = message; self.isActiveProfile = isActiveProfile }
    public let profileName: String
    public let hermesHomePath: String
    public let state: UsageSummaryState
    public let sessionCount: Int
    public let inputTokens: Int64
    public let outputTokens: Int64
    public let cacheReadTokens: Int64
    public let cacheWriteTokens: Int64
    public let reasoningTokens: Int64
    public let databasePath: String?
    public let message: String?
    public let isActiveProfile: Bool

    public var id: String { profileName }

    public var cacheTokensTotal: Int64 {
        cacheReadTokens + cacheWriteTokens
    }

    public var inputOutputTokensTotal: Int64 {
        inputTokens + outputTokens
    }

    public var allTokenCategoriesTotal: Int64 {
        inputOutputTokensTotal + cacheTokensTotal + reasoningTokens
    }
}

public extension UsageSummary {
    public var totalTokens: Int64 {
        inputTokens + outputTokens
    }

    var cacheTokensTotal: Int64 {
        cacheReadTokens + cacheWriteTokens
    }

    var allTokenCategoriesTotal: Int64 {
        totalTokens + cacheTokensTotal + reasoningTokens
    }

    var averageTokensPerSession: Int64 {
        guard sessionCount > 0 else { return 0 }
        return Int64((Double(totalTokens) / Double(sessionCount)).rounded())
    }
}