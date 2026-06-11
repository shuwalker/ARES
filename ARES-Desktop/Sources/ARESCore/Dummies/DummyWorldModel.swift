import Foundation

/// Synthetic world model: generates random scene state.
public final class DummyWorldModel: WorldPerception, @unchecked Sendable {
    public let capabilities: Set<String> = ["objectTracking", "relationships"]

    public init() {
        print("🤖 [DUMMY] WorldModel: initialized")
    }

    public func getState() async throws -> SceneState {
        SceneState(
            objects: [
                SceneObject(kind: "person", label: "user", confidence: 0.95),
                SceneObject(kind: "screen", label: "monitor", confidence: 0.9)
            ],
            relationships: [
                SpatialRelationship(subject: "user", relation: "facing", object: "monitor")
            ]
        )
    }

    public func updateFromPerception(_ landmarks: FaceLandmarks, _ prosody: Prosody) async throws {
        print("🤖 [DUMMY] WorldModel updated from perception (\(landmarks.points.count) landmarks, pitch \(Int(prosody.pitch))Hz)")
    }

    public func queryObjects(kind: String) async throws -> [SceneObject] {
        print("🤖 [DUMMY] WorldModel query: \(kind)")
        return [SceneObject(kind: kind, label: kind)]
    }

    public func getRelationships() async throws -> [SpatialRelationship] {
        [SpatialRelationship(subject: "user", relation: "in", object: "room")]
    }
}
