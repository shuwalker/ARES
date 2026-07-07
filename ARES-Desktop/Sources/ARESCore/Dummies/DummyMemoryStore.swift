import Foundation

/// In-memory MemoryStore for testing. No persistence.
public final class DummyMemoryStore: MemoryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var memories: [String: Memory] = [:]

    public let capabilities: Set<String> = ["memory", "search", "update", "delete"]

    public init() {}

    public func store(_ memory: Memory) async throws -> String {
        lock.withLock {
            memories[memory.id] = memory
        }
        print("🤖 [DUMMY] Stored memory: \(memory.id) '\(memory.content.prefix(40))...'")
        return memory.id
    }

    public func retrieve(query: String, limit: Int) async throws -> [Memory] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let results = lock.withLock { Array(memories.values) }
            .filter { normalizedQuery.isEmpty || $0.content.lowercased().contains(normalizedQuery) }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
        print("🤖 [DUMMY] Retrieved \(results.count) memories for '\(query)'")
        return Array(results)
    }

    public func update(_ id: String, with updates: [String: AnyCodable]) async throws {
        try lock.withLock {
            guard let memory = memories[id] else {
                throw NSError(domain: "DummyMemoryStore", code: -1, userInfo: ["message": "Not found"])
            }
            var newContext = memory.context
            updates.forEach { newContext[$0.key] = $0.value }
            let newContent: String
            if case .string(let content) = updates["content"] {
                newContent = content
            } else {
                newContent = memory.content
            }
            memories[id] = Memory(
                id: id,
                content: newContent,
                context: newContext,
                timestamp: Date(),
                embedding: memory.embedding
            )
        }
        print("🤖 [DUMMY] Updated memory: \(id)")
    }

    public func delete(_ id: String) async throws {
        _ = lock.withLock {
            memories.removeValue(forKey: id)
        }
        print("🤖 [DUMMY] Deleted memory: \(id)")
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
