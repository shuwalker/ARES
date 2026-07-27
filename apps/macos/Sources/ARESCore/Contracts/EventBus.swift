import Foundation

/// EventBus protocol: pub/sub routing between bricks.
/// Replaces direct brick-to-brick calls. Enables:
/// - Decoupling (perception doesn't know who cares about landmarks)
/// - Multiplexing (many subscribers to one event)
/// - Async fanout (subscribers run in background)
/// - Cross-module isolation (no imports except protocol)
public protocol EventBus: AnyObject, Sendable {
    /// Subscribe to events of a specific type.
    /// Returns AsyncSequence; break to unsubscribe.
    func subscribe<T: Codable & Sendable>(_ eventType: T.Type) -> AsyncStream<T>

    /// Publish an event. Async; subscribers notified immediately.
    func publish<T: Codable & Sendable>(_ event: T) async throws

    /// Query event history (last N events of type T).
    func history<T: Codable & Sendable>(_ eventType: T.Type, limit: Int) async throws -> [T]

    /// What can this bus do?
    /// Examples: ["subscribe", "publish", "history", "filtering"]
    var capabilities: Set<String> { get }
}

// MARK: - Standard Event Types

/// Perception event: landmarks arrived.
public struct PerceptionEvent: Codable, Sendable, Equatable {
    public let landmarks: FaceLandmarks
    public let prosody: Prosody
    public let timestamp: Date

    public init(landmarks: FaceLandmarks, prosody: Prosody, timestamp: Date = Date()) {
        self.landmarks = landmarks
        self.prosody = prosody
        self.timestamp = timestamp
    }
}

/// Mimicry event: expression computed.
public struct MimicryEvent: Codable, Sendable, Equatable {
    public let frame: MimicryFrame
    public let timestamp: Date

    public init(frame: MimicryFrame, timestamp: Date = Date()) {
        self.frame = frame
        self.timestamp = timestamp
    }
}

/// Embodiment event: command executed.
public struct EmbodimentEvent: Codable, Sendable, Equatable {
    public let action: String                  // "expression", "gaze", "speak", "approval"
    public let success: Bool
    public let timestamp: Date

    public init(action: String, success: Bool, timestamp: Date = Date()) {
        self.action = action
        self.success = success
        self.timestamp = timestamp
    }
}

/// Memory event: memory stored/retrieved.
public struct MemoryEvent: Codable, Sendable, Equatable {
    public let action: String                  // "store", "retrieve", "update", "delete"
    public let memoryId: String
    public let timestamp: Date

    public init(action: String, memoryId: String, timestamp: Date = Date()) {
        self.action = action
        self.memoryId = memoryId
        self.timestamp = timestamp
    }
}

/// Reasoning event: brain responded.
public struct ReasoningEvent: Codable, Sendable, Equatable {
    public let prompt: String
    public let response: String
    public let tokensUsed: Int
    public let timestamp: Date

    public init(
        prompt: String,
        response: String,
        tokensUsed: Int = 0,
        timestamp: Date = Date()
    ) {
        self.prompt = prompt
        self.response = response
        self.tokensUsed = tokensUsed
        self.timestamp = timestamp
    }
}

/// World event: scene state updated.
public struct WorldEvent: Codable, Sendable, Equatable {
    public let state: SceneState
    public let timestamp: Date

    public init(state: SceneState, timestamp: Date = Date()) {
        self.state = state
        self.timestamp = timestamp
    }
}
