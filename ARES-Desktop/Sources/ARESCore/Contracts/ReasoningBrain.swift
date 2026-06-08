#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// ReasoningBrain protocol: planning, responding, and reflection.
/// Conforming types: HermesAgentBrain, ClaudeApiBrain, LocalLlamaBrain
public protocol ReasoningBrain: AnyObject, Sendable {
    /// Generate a plan given world state and context.
    /// Returns ordered tasks with dependencies and approval requirements.
    func plan(context: SceneUnderstanding) async throws -> [AgentTask]

    /// Generate a response to user input.
    /// May use memory, tools, and world state internally.
    func respond(to input: String, context: ConversationContext) async throws -> String

    /// Reflect on an experience: consolidate memories, learn patterns.
    func reflect(on experience: Experience) async throws

    /// What can this brain do?
    /// Examples: ["tools", "memory", "streaming", "reflection"]
    var capabilities: Set<String> { get }
}

/// A task: something the brain wants to do.
public struct AgentTask: Codable, Sendable, Equatable {
    public let id: String
    public let description: String
    public let requiredCapabilities: Set<String>
    public let approvalRequired: Bool
    public let estimatedDuration: TimeInterval?

    public init(
        id: String = UUID().uuidString,
        description: String,
        requiredCapabilities: Set<String> = [],
        approvalRequired: Bool = false,
        estimatedDuration: TimeInterval? = nil
    ) {
        self.id = id
        self.description = description
        self.requiredCapabilities = requiredCapabilities
        self.approvalRequired = approvalRequired
        self.estimatedDuration = estimatedDuration
    }
}

/// Scene understanding: world state for reasoning (distinct from WorldPerception protocol).
public struct SceneUnderstanding: Codable, Sendable, Equatable {
    public struct Object: Codable, Sendable, Equatable {
        public let id: String
        public let kind: String                     // "person", "object", "animal", etc.
        public let position: CGPoint
        public let attributes: [String: AnyCodable]

        public init(
            id: String = UUID().uuidString,
            kind: String,
            position: CGPoint = .zero,
            attributes: [String: AnyCodable] = [:]
        ) {
            self.id = id
            self.kind = kind
            self.position = position
            self.attributes = attributes
        }
    }

    public let objects: [Object]
    public let relationships: [Relationship]
    public let timestamp: Date

    public struct Relationship: Codable, Sendable, Equatable {
        public let subject: String
        public let relation: String
        public let object: String

        public init(subject: String, relation: String, object: String) {
            self.subject = subject
            self.relation = relation
            self.object = object
        }
    }

    public init(
        objects: [Object] = [],
        relationships: [Relationship] = [],
        timestamp: Date = Date()
    ) {
        self.objects = objects
        self.relationships = relationships
        self.timestamp = timestamp
    }
}

/// Conversation context: previous messages, user info, tone.
public struct ConversationContext: Codable, Sendable {
    public let messages: [Message]
    public let userInfo: [String: AnyCodable]
    public let tone: String                        // "formal", "casual", "technical", etc.
    public let parentTask: String?                 // Task ID this conversation belongs to
    public let sessionID: String?                  // Gateway session ID for multi-turn continuity
    public let model: String?                      // Model name or identifier

    public init(
        messages: [Message] = [],
        userInfo: [String: AnyCodable] = [:],
        tone: String = "casual",
        parentTask: String? = nil,
        sessionID: String? = nil,
        model: String? = nil
    ) {
        self.messages = messages
        self.userInfo = userInfo
        self.tone = tone
        self.parentTask = parentTask
        self.sessionID = sessionID
        self.model = model
    }
}

/// An experience: a completed action + outcome + feedback.
public struct Experience: Codable, Sendable {
    public let taskId: String
    public let action: String
    public let outcome: String                     // "success", "failed", "partial"
    public let feedback: String?
    public let timestamp: Date

    public init(
        taskId: String,
        action: String,
        outcome: String,
        feedback: String? = nil,
        timestamp: Date = Date()
    ) {
        self.taskId = taskId
        self.action = action
        self.outcome = outcome
        self.feedback = feedback
        self.timestamp = timestamp
    }
}

/// A message in a conversation.
public struct Message: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
        case system
    }

    public let id: String
    public let role: Role
    public let content: String
    public let attachments: [Attachment]
    public let timestamp: Date
    public let metadata: [String: AnyCodable]

    public init(
        id: String = UUID().uuidString,
        role: Role,
        content: String,
        attachments: [Attachment] = [],
        timestamp: Date = Date(),
        metadata: [String: AnyCodable] = [:]
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.timestamp = timestamp
        self.metadata = metadata
    }
}

/// An attachment: image, audio, structured data, etc.
public enum Attachment: Codable, Sendable, Equatable {
    case image(Data, mimeType: String)             // PNG, JPEG, WebP, etc.
    case audio(AudioBuffer)
    case text(String)
    case structured([String: AnyCodable])

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "image":
            let data = try container.decode(Data.self, forKey: .data)
            let mimeType = try container.decode(String.self, forKey: .mimeType)
            self = .image(data, mimeType: mimeType)
        case "audio":
            let buffer = try container.decode(AudioBuffer.self, forKey: .data)
            self = .audio(buffer)
        case "text":
            let text = try container.decode(String.self, forKey: .data)
            self = .text(text)
        case "structured":
            let structured = try container.decode([String: AnyCodable].self, forKey: .data)
            self = .structured(structured)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown attachment type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .image(let data, let mimeType):
            try container.encode("image", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case .audio(let buffer):
            try container.encode("audio", forKey: .type)
            try container.encode(buffer, forKey: .data)
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .data)
        case .structured(let dict):
            try container.encode("structured", forKey: .type)
            try container.encode(dict, forKey: .data)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type
        case data
        case mimeType
    }
}

