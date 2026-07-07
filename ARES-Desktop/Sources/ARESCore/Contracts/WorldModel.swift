import CoreGraphics
import Foundation

/// World protocol: maintains scene graph and spatial reasoning state.
/// Distinct from Perceiver (raw sensors) — this is *understanding* what you see.
/// Conforming types: VisionWorldModel, GraphWorldModel, DummyWorldModel
public protocol WorldPerception: AnyObject, Sendable {
    /// Get current scene understanding.
    func getState() async throws -> SceneState

    /// Update scene with new perception.
    func updateFromPerception(_ landmarks: FaceLandmarks, _ prosody: Prosody) async throws

    /// Query objects by kind or relationship.
    /// Examples: "people", "objects", "animals", "screens"
    func queryObjects(kind: String) async throws -> [SceneObject]

    /// Get spatial relationships between objects.
    /// Returns: [(subject: A, relation: "near", object: B), ...]
    func getRelationships() async throws -> [SpatialRelationship]

    /// What can this world model do?
    /// Examples: ["objectTracking", "relationships", "planning"]
    var capabilities: Set<String> { get }
}

/// Scene state: objects + relationships + metadata.
public struct SceneState: Codable, Sendable, Equatable {
    public let objects: [SceneObject]
    public let relationships: [SpatialRelationship]
    public let timestamp: Date
    public let confidence: Double              // 0...1 overall scene understanding

    public init(
        objects: [SceneObject] = [],
        relationships: [SpatialRelationship] = [],
        timestamp: Date = Date(),
        confidence: Double = 0.5
    ) {
        self.objects = objects
        self.relationships = relationships
        self.timestamp = timestamp
        self.confidence = max(0, min(1, confidence))
    }
}

/// An object in the scene.
public struct SceneObject: Codable, Sendable, Equatable {
    public let id: String
    public let kind: String                    // "person", "screen", "object", "animal"
    public let label: String                   // "user", "monitor", "coffee cup", "cat"
    public let boundingBox: CGRect
    public let confidence: Double              // 0...1 detection confidence
    public let attributes: [String: AnyCodable]

    public init(
        id: String = UUID().uuidString,
        kind: String,
        label: String,
        boundingBox: CGRect = .zero,
        confidence: Double = 0.8,
        attributes: [String: AnyCodable] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.boundingBox = boundingBox
        self.confidence = max(0, min(1, confidence))
        self.attributes = attributes
    }
}

/// Spatial relationship between two objects.
public struct SpatialRelationship: Codable, Sendable, Equatable {
    public let subject: String                 // Object ID
    public let relation: String                // "near", "above", "facing", "holding"
    public let object: String                  // Object ID
    public let confidence: Double

    public init(
        subject: String,
        relation: String,
        object: String,
        confidence: Double = 0.8
    ) {
        self.subject = subject
        self.relation = relation
        self.object = object
        self.confidence = max(0, min(1, confidence))
    }
}
