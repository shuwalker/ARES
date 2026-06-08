import Foundation

/// In-memory pub/sub event bus for testing.
public final class DummyEventBus: EventBus, @unchecked Sendable {
    private var subscribers: [String: [AnySendable]] = [:]
    private var history: [[String: AnyCodable]] = []

    public var capabilities: Set<String> { ["subscribe", "publish", "history"] }

    public init() {
        print("🤖 [DUMMY] EventBus: initialized")
    }

    public func subscribe<T: Codable & Sendable>(_ eventType: T.Type) -> AsyncStream<T> {
        let key = String(describing: T.self)
        print("🤖 [DUMMY] EventBus subscribe: \(key)")

        return AsyncStream { continuation in
            // In a real impl, store the continuation and yield to it on publish
            // For dummy, just return empty stream
            continuation.finish()
        }
    }

    public func publish<T: Codable & Sendable>(_ event: T) async throws {
        let key = String(describing: T.self)
        print("🤖 [DUMMY] EventBus publish: \(key)")
    }

    public func history<T: Codable & Sendable>(_ eventType: T.Type, limit: Int) async throws -> [T] {
        let key = String(describing: T.self)
        print("🤖 [DUMMY] EventBus history: \(key) (limit \(limit))")
        return []
    }
}

// Helper for type-erased storage
private protocol AnySendable: Sendable {}
