import Foundation

struct MCPServer: Identifiable, Codable, Sendable {
    let id: String
    var name: String
    var command: String
    var args: [String]
    var enabled: Bool
    var trustLevel: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case command
        case args
        case enabled
        case trustLevel = "trust_level"
    }
}

struct MCPMarketplaceItem: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let description: String
    let trustLevel: String
    let source: String?
    let installCommand: String?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case trustLevel = "trust_level"
        case source
        case installCommand = "install_command"
    }
}

struct MCPServerCreate: Encodable, Sendable {
    let name: String
    let command: String
    let args: [String]
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case command
        case args
        case enabled
    }
}

struct MCPServerPatch: Encodable, Sendable {
    let enabled: Bool?

    enum CodingKeys: String, CodingKey {
        case enabled
    }
}
