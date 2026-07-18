import Foundation

/// In-memory pub/sub event bus for testing.
public final class DummyEventBus: EventBus, @unchecked Sendable {
    private let lock = NSLock()
    private var subscribers: [String: [UUID: AnyEventSubscriber]] = [:]
    private var eventHistory: [String: [Data]] = [:]

    public var capabilities: Set<String> { ["subscribe", "publish", "history"] }

    public init() {
        print("🤖 [DUMMY] EventBus: initialized")
    }

    public func subscribe<T: Codable & Sendable>(_ eventType: T.Type) -> AsyncStream<T> {
        let key = String(describing: T.self)
        print("🤖 [DUMMY] EventBus subscribe: \(key)")

        return AsyncStream { continuation in
            let id = UUID()
            let subscriber = EventSubscriber<T>(continuation: continuation)
            lock.withLock {
                subscribers[key, default: [:]][id] = subscriber
            }
            continuation.onTermination = { [weak self] _ in
                self?.removeSubscriber(id, forKey: key)
            }
        }
    }

    public func publish<T: Codable & Sendable>(_ event: T) async throws {
        let key = String(describing: T.self)
        print("🤖 [DUMMY] EventBus publish: \(key)")
        let encoded = try JSONEncoder().encode(event)
        let currentSubscribers = lock.withLock { () -> [AnyEventSubscriber] in
            eventHistory[key, default: []].append(encoded)
            return Array(subscribers[key, default: [:]].values)
        }
        currentSubscribers.forEach { $0.yield(event) }
    }

    public func history<T: Codable & Sendable>(_ eventType: T.Type, limit: Int) async throws -> [T] {
        let key = String(describing: T.self)
        print("🤖 [DUMMY] EventBus history: \(key) (limit \(limit))")
        let encoded = lock.withLock {
            Array(eventHistory[key, default: []].suffix(max(0, limit)))
        }
        return try encoded.map { try JSONDecoder().decode(T.self, from: $0) }
    }

    private func removeSubscriber(_ id: UUID, forKey key: String) {
        lock.withLock {
            subscribers[key]?[id] = nil
            if subscribers[key]?.isEmpty == true {
                subscribers[key] = nil
            }
        }
    }
}

// Helper for type-erased storage
private protocol AnyEventSubscriber: Sendable {
    func yield<T: Sendable>(_ event: T)
}

private final class EventSubscriber<Event: Sendable>: AnyEventSubscriber, @unchecked Sendable {
    private let continuation: AsyncStream<Event>.Continuation

    init(continuation: AsyncStream<Event>.Continuation) {
        self.continuation = continuation
    }

    func yield<T: Sendable>(_ event: T) {
        guard let typedEvent = event as? Event else { return }
        continuation.yield(typedEvent)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
