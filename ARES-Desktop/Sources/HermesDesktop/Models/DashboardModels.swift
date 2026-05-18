import Foundation

extension JSONValue {
    var stringValueOrDescription: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .number(let d): return String(d)
        case .bool(let b): return String(b)
        case .null: return "null"
        case .array(let arr): return arr.map(\.stringValueOrDescription).joined(separator: ", ")
        case .object(let dict): return dict.map { "\($0.key): \($0.value.stringValueOrDescription)" }.joined(separator: ", ")
        }
    }
}

// MARK: - Config

struct ConfigResponse: Decodable {
    let config: [String: JSONValue]
    let schema: ConfigSchema?

    enum CodingKeys: String, CodingKey {
        case config, schema
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        config = try container.decode([String: JSONValue].self, forKey: .config)
        schema = try container.decodeIfPresent(ConfigSchema.self, forKey: .schema)
    }
}

struct ConfigSchema: Decodable {
    let sections: [ConfigSchemaSection]?

    enum CodingKeys: String, CodingKey {
        case sections
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sections = try container.decodeIfPresent([ConfigSchemaSection].self, forKey: .sections)
    }
}

struct ConfigSchemaSection: Decodable, Identifiable {
    let name: String
    let icon: String?
    let fields: [ConfigSchemaField]?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, icon, fields
    }
}

struct ConfigSchemaField: Decodable, Identifiable {
    let key: String
    let label: String?
    let type: String?
    let options: [String]?
    let defaultValue: JSONValue?

    var id: String { key }

    enum CodingKeys: String, CodingKey {
        case key, label, type, options
        case defaultValue = "default"
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

struct EnvResponse: Decodable {
    let env: [String: String?]
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

struct LogsResponse: Decodable {
    let lines: [LogLine]
    let file: String?

    enum CodingKeys: String, CodingKey {
        case lines, file
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // API may return lines as a raw string or as an array
        if let lineArray = try? container.decode([LogLine].self, forKey: .lines) {
            lines = lineArray
        } else if let rawString = try? container.decode(String.self, forKey: .lines) {
            lines = rawString.components(separatedBy: "\n").filter { !$0.isEmpty }.map { LogLine(text: $0, level: nil, timestamp: nil) }
        } else {
            lines = []
        }
        file = try container.decodeIfPresent(String.self, forKey: .file)
    }
}

struct LogLine: Decodable {
    let text: String
    let level: String?
    let timestamp: String?

    var identifier: String { (timestamp ?? "") + text.prefix(100) }

    var levelColor: String {
        guard let lvl = level?.uppercased() else { return "default" }
        if lvl.contains("ERROR") || lvl.contains("CRITICAL") || lvl.contains("FATAL") { return "error" }
        if lvl.contains("WARNING") || lvl.contains("WARN") { return "warning" }
        if lvl.contains("DEBUG") { return "debug" }
        return "info"
    }
}

// MARK: - Models

struct ModelsResponse: Decodable {
    let current: String
    let available: [ModelOption]
    let auxiliary: [String: String]?

    enum CodingKeys: String, CodingKey {
        case current, available, auxiliary
    }
}

struct ModelOption: Decodable, Identifiable {
    let modelId: String
    let name: String?
    let provider: String?

    var id: String { modelId }

    enum CodingKeys: String, CodingKey {
        case modelId = "id", name, provider
    }
}

struct ModelsAnalyticsResponse: Decodable {
    let models: [ModelAnalytics]?

    enum CodingKeys: String, CodingKey {
        case models
    }
}

struct ModelAnalytics: Decodable, Identifiable {
    let model: String
    let inputTokens: Int?
    let outputTokens: Int?
    let totalCost: Double?
    let sessionCount: Int?

    var id: String { model }

    enum CodingKeys: String, CodingKey {
        case model
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalCost = "total_cost"
        case sessionCount = "session_count"
    }
}

// MARK: - Profiles

struct ProfilesResponse: Decodable {
    let profiles: [ProfileInfo]
}

struct ProfileInfo: Decodable, Identifiable {
    let name: String
    let path: String?
    let isDefault: Bool?
    let exists: Bool?

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, path
        case isDefault = "is_default"
        case exists
    }
}

// MARK: - Gateway Status

struct StatusResponse: Decodable {
    let status: String
    let platform: String?
    let activeSessions: Int?
    let version: String?

    enum CodingKeys: String, CodingKey {
        case status, platform, version
        case activeSessions = "active_sessions"
    }
}