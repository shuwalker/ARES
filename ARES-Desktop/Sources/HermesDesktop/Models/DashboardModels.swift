import Foundation

// MARK: - Config

/// GET /api/config returns a flat dictionary.
/// The response is NOT wrapped in a top-level key — it's just the config dict directly.
typealias ConfigResponse = [String: JSONValue]

/// GET /api/config/schema returns { "fields": { "key": { "type", "description", "category", ... } } }
struct ConfigSchemaResponse: Decodable {
    let fields: [String: ConfigSchemaField]?
}

struct ConfigSchemaField: Decodable {
    let type: String?
    let description: String?
    let category: String?
    let options: [String]?
    let `default`: JSONValue?

    enum CodingKeys: String, CodingKey {
        case type, description, category, options, `default`
    }
}

/// A categorized config section for display.
struct ConfigCategory: Identifiable {
    let name: String
    let icon: String
    let fields: [ConfigField]

    var id: String { name }
}

struct ConfigField: Identifiable {
    let key: String
    let value: String
    let originalValue: String
    let typeHint: String?

    var id: String { key }
}

// MARK: - Environment Variables

/// GET /api/env returns a flat dict where each key maps to an env var info object.
typealias EnvResponse = [String: EnvVarInfo]

struct EnvVarInfo: Decodable {
    let isSet: Bool?
    let redactedValue: String?
    let description: String?
    let url: String?
    let category: String?
    let isPassword: Bool?
    let tools: [String]?
    let advanced: Bool?

    enum CodingKeys: String, CodingKey {
        case isSet = "is_set"
        case redactedValue = "redacted_value"
        case description, url, category
        case isPassword = "is_password"
        case tools, advanced
    }
}

struct EnvEntry: Identifiable {
    let key: String
    var value: String?
    var isRevealed: Bool

    var id: String { key }
    var displayValue: String {
        guard let v = value, !v.isEmpty else { return "(empty)" }
        return isRevealed ? v : String(repeating: "•", count: min(v.count, 20))
    }
    var isSet: Bool { value != nil && !value!.isEmpty }
}

// MARK: - Logs

/// GET /api/logs?file=agent&lines=200&level=ALL returns { "file": "agent", "lines": ["...", ...] }
struct LogsResponse: Decodable {
    let file: String?
    let lines: [String]
}

/// Parsed log line for display in the UI.
struct LogLine: Identifiable {
    let text: String
    let level: String?
    let timestamp: String?
    let index: Int

    var id: Int { index }
}

// MARK: - Models

/// GET /api/model/info returns the current active model info.
struct ModelInfoResponse: Decodable {
    let model: String
    let provider: String?
    let autoContextLength: Int?
    let configContextLength: Int?
    let effectiveContextLength: Int?
    let capabilities: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
        case model, provider, capabilities
        case autoContextLength = "auto_context_length"
        case configContextLength = "config_context_length"
        case effectiveContextLength = "effective_context_length"
    }
}

/// GET /api/model/options returns { "providers": [...] }
struct ModelOptionsResponse: Decodable {
    let providers: [ModelProvider]
}

struct ModelProvider: Decodable, Identifiable {
    let slug: String
    let name: String
    let isCurrent: Bool?
    let isUserDefined: Bool?
    let models: [String]?
    let totalModels: Int?
    let source: String?

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, name, models, source
        case isCurrent = "is_current"
        case isUserDefined = "is_user_defined"
        case totalModels = "total_models"
    }
}

/// GET /api/model/auxiliary returns { "tasks": [...], "main": {...} }
struct AuxiliaryModelsResponse: Decodable {
    let tasks: [AuxiliaryTask]?
    let main: AuxiliaryMain?
}

struct AuxiliaryTask: Decodable, Identifiable {
    let task: String
    let provider: String?
    let model: String?
    let baseUrl: String?

    var id: String { task }

    enum CodingKeys: String, CodingKey {
        case task, provider, model
        case baseUrl = "base_url"
    }
}

struct AuxiliaryMain: Decodable {
    let provider: String?
    let model: String?
}

/// POST /api/model/set body
struct ModelSetRequest: Encodable {
    let model: String
    let provider: String?

    enum CodingKeys: String, CodingKey {
        case model, provider
    }
}

// MARK: - Analytics Daily

struct AnalyticsDailyEntry: Decodable, Identifiable {
    let day: String
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadTokens: Int?
    let reasoningTokens: Int?
    let estimatedCost: Double?
    let actualCost: Double?
    let sessions: Int?
    let apiCalls: Int?

    var id: String { day }

    enum CodingKeys: String, CodingKey {
        case day
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case reasoningTokens = "reasoning_tokens"
        case estimatedCost = "estimated_cost"
        case actualCost = "actual_cost"
        case sessions
        case apiCalls = "api_calls"
    }
}

struct AnalyticsModelEntry: Decodable, Identifiable {
    let model: String
    let inputTokens: Int?
    let outputTokens: Int?
    let estimatedCost: Double?
    let sessions: Int?
    let apiCalls: Int?

    var id: String { model }

    enum CodingKeys: String, CodingKey {
        case model
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case estimatedCost = "estimated_cost"
        case sessions
        case apiCalls = "api_calls"
    }
}

struct AnalyticsSkillEntry: Decodable, Identifiable {
    let skill: String
    let viewCount: Int?
    let manageCount: Int?
    let totalCount: Int?
    let percentage: Double?
    let lastUsedAt: Double?

    var id: String { skill }

    enum CodingKeys: String, CodingKey {
        case skill
        case viewCount = "view_count"
        case manageCount = "manage_count"
        case totalCount = "total_count"
        case percentage
        case lastUsedAt = "last_used_at"
    }
}

struct AnalyticsSkillsSummary: Decodable {
    let totalSkillLoads: Int?
    let totalSkillEdits: Int?
    let totalSkillActions: Int?
    let distinctSkillsUsed: Int?
    let topSkills: [AnalyticsSkillEntry]?

    enum CodingKeys: String, CodingKey {
        case totalSkillLoads = "total_skill_loads"
        case totalSkillEdits = "total_skill_edits"
        case totalSkillActions = "total_skill_actions"
        case distinctSkillsUsed = "distinct_skills_used"
        case topSkills = "top_skills"
    }
}

struct AnalyticsTotal: Decodable {
    let totalInput: Int?
    let totalOutput: Int?
    let totalCacheRead: Int?
    let totalReasoning: Int?
    let totalEstimatedCost: Double?
    let totalActualCost: Double?
    let totalSessions: Int?
    let totalApiCalls: Int?

    enum CodingKeys: String, CodingKey {
        case totalInput = "total_input"
        case totalOutput = "total_output"
        case totalCacheRead = "total_cache_read"
        case totalReasoning = "total_reasoning"
        case totalEstimatedCost = "total_estimated_cost"
        case totalActualCost = "total_actual_cost"
        case totalSessions = "total_sessions"
        case totalApiCalls = "total_api_calls"
    }
}

struct AnalyticsResponse: Decodable {
    let daily: [AnalyticsDailyEntry]?
    let byModel: [AnalyticsModelEntry]?
    let totals: AnalyticsTotal?
    let skills: AnalyticsSkillsSummary?

    enum CodingKeys: String, CodingKey {
        case daily
        case byModel = "by_model"
        case totals
        case skills
    }
}

// MARK: - Models Analytics

/// GET /api/analytics/models?days=7
struct ModelsAnalyticsResponse: Decodable {
    let models: [ModelsAnalyticsModelEntry]?
    let totals: ModelsAnalyticsTotals?
}

struct ModelsAnalyticsTotals: Decodable {
    let distinctModels: Int?
    let totalInput: Int?
    let totalOutput: Int?
    let totalCacheRead: Int?
    let totalReasoning: Int?
    let totalEstimatedCost: Double?
    let totalActualCost: Double?
    let totalSessions: Int?
    let totalApiCalls: Int?
    let totalToolCalls: Int?

    enum CodingKeys: String, CodingKey {
        case distinctModels = "distinct_models"
        case totalInput = "total_input"
        case totalOutput = "total_output"
        case totalCacheRead = "total_cache_read"
        case totalReasoning = "total_reasoning"
        case totalEstimatedCost = "total_estimated_cost"
        case totalActualCost = "total_actual_cost"
        case totalSessions = "total_sessions"
        case totalApiCalls = "total_api_calls"
        case totalToolCalls = "total_tool_calls"
    }
}

struct ModelsAnalyticsModelEntry: Decodable, Identifiable {
    let model: String
    let provider: String?
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheReadTokens: Int?
    let reasoningTokens: Int?
    let estimatedCost: Double?
    let actualCost: Double?
    let sessions: Int?
    let apiCalls: Int?
    let toolCalls: Int?
    let lastUsedAt: Double?
    let avgTokensPerSession: Int?
    let capabilities: [String: JSONValue]?

    var id: String { model }

    enum CodingKeys: String, CodingKey {
        case model, provider, capabilities
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case reasoningTokens = "reasoning_tokens"
        case estimatedCost = "estimated_cost"
        case actualCost = "actual_cost"
        case sessions
        case apiCalls = "api_calls"
        case toolCalls = "tool_calls"
        case lastUsedAt = "last_used_at"
        case avgTokensPerSession = "avg_tokens_per_session"
    }
}

/// Legacy alias kept for backward compatibility.
typealias ModelAnalytics = ModelsAnalyticsModelEntry

// MARK: - Profiles

/// GET /api/profiles returns { "profiles": [...] }
struct ProfilesResponse: Decodable {
    let profiles: [ProfileInfo]
}

struct ProfileInfo: Decodable, Identifiable {
    let name: String
    let path: String?
    let isDefault: Bool?
    let model: String?
    let provider: String?
    let hasEnv: Bool?
    let skillCount: Int?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, path, model, provider
        case isDefault = "is_default"
        case hasEnv = "has_env"
        case skillCount = "skill_count"
    }
}

// MARK: - Gateway Status

/// GET /api/status — public endpoint (no auth required)
struct StatusResponse: Decodable {
    let version: String?
    let releaseDate: String?
    let hermesHome: String?
    let configPath: String?
    let envPath: String?
    let configVersion: Int?
    let latestConfigVersion: Int?
    let gatewayRunning: Bool?
    let gatewayPid: Int?
    let gatewayState: String?
    let gatewayPlatforms: [String: PlatformStatus]?
    let activeSessions: Int?

    enum CodingKeys: String, CodingKey {
        case version
        case releaseDate = "release_date"
        case hermesHome = "hermes_home"
        case configPath = "config_path"
        case envPath = "env_path"
        case configVersion = "config_version"
        case latestConfigVersion = "latest_config_version"
        case gatewayRunning = "gateway_running"
        case gatewayPid = "gateway_pid"
        case gatewayState = "gateway_state"
        case gatewayPlatforms = "gateway_platforms"
        case activeSessions = "active_sessions"
    }
}

struct PlatformStatus: Decodable {
    let state: String?
    let errorCode: String?
    let errorMessage: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case state
        case errorCode = "error_code"
        case errorMessage = "error_message"
        case updatedAt = "updated_at"
    }
}

// MARK: - System Controls

/// Response from POST /api/gateway/restart and POST /api/hermes/update
struct ActionResponse: Decodable {
    let success: Bool
    let message: String?
}

/// Response from GET /api/actions/{name}/status
struct ActionStatusResponse: Decodable {
    let name: String?
    let status: String?
    let lines: [String]?
    let lastRunAt: String?

    enum CodingKeys: String, CodingKey {
        case name, status, lines
        case lastRunAt = "last_run_at"
    }
}