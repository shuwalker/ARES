import Foundation

/// In-memory MemoryStore for testing. No persistence.
public final class DummyMemoryStore: MemoryStore, @unchecked Sendable {
    private var memories: [String: Memory] = [:]

    public let capabilities: Set<String> = ["search"]

    public init() {}

    public func store(_ memory: Memory) async throws -> String {
        memories[memory.id] = memory
        print("🤖 [DUMMY] Stored memory: \(memory.id) '\(memory.content.prefix(40))...'")
        return memory.id
    }

    public func retrieve(query: String, limit: Int) async throws -> [Memory] {
        let results = memories.values
            .filter { $0.content.contains(query) }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
        print("🤖 [DUMMY] Retrieved \(results.count) memories for '\(query)'")
        return Array(results)
    }

    public func update(_ id: String, with updates: [String: AnyCodable]) async throws {
        guard var memory = memories[id] else {
            throw NSError(domain: "DummyMemoryStore", code: -1, userInfo: ["message": "Not found"])
        }
        var newContext = memory.context
        updates.forEach { newContext[$0.key] = $0.value }
        memories[id] = Memory(
            id: id,
            content: memory.content,
            context: newContext,
            timestamp: memory.timestamp,
            embedding: memory.embedding
        )
        print("🤖 [DUMMY] Updated memory: \(id)")
    }

    public func delete(_ id: String) async throws {
        memories.removeValue(forKey: id)
        print("🤖 [DUMMY] Deleted memory: \(id)")
    }
}
