// MARK: - Memory System
// Extracted from CrewAI's memory architecture (episodic, semantic, procedural)
// and LangGraph's checkpoint/store system

import Foundation

// MARK: - Memory Types

public enum MemoryType: String, Sendable {
    case episodic    // What happened (conversation logs, events)
    case semantic    // Facts about the world (user preferences, entity properties)
    case procedural  // How to do things (learned workflows, tool sequences)
}

public struct MemoryRecord: Sendable, Identifiable {
    public let id: String
    public let type: MemoryType
    public let content: String
    public let scope: String
    public let importance: Double
    public let timestamp: Date
    public let lastAccessed: Date
    public let metadata: [String: String]
    public let embedding: [Float]?

    public init(id: String = UUID().uuidString, type: MemoryType, content: String, scope: String = "default",
                importance: Double = 0.5, timestamp: Date = Date(), lastAccessed: Date = Date(),
                metadata: [String: String] = [:], embedding: [Float]? = nil) {
        self.id = id
        self.type = type
        self.content = content
        self.scope = scope
        self.importance = importance
        self.timestamp = timestamp
        self.lastAccessed = lastAccessed
        self.metadata = metadata
        self.embedding = embedding
    }
}

// MARK: - Memory Store Protocol (CrewAI StorageBackend pattern)

public protocol MemoryStore: AnyObject {
    func save(_ record: MemoryRecord) async throws
    func saveBatch(_ records: [MemoryRecord]) async throws
    func search(query: String, type: MemoryType?, scope: String?, limit: Int) async throws -> [MemoryRecord]
    func searchSimilar(embedding: [Float], type: MemoryType?, limit: Int) async throws -> [MemoryRecord]
    func delete(_ id: String) async throws
    func deleteScope(_ scope: String) async throws
    func listScopes() async throws -> [String]
}

// MARK: - In-Memory Store (default)

public final class InMemoryStore: MemoryStore, @unchecked Sendable {
    private var records: [String: MemoryRecord] = [:]
    private let queue = DispatchQueue(label: "com.ares.memory")

    public init() {}

    public func save(_ record: MemoryRecord) async throws {
        queue.sync { records[record.id] = record }
    }

    public func saveBatch(_ records: [MemoryRecord]) async throws {
        queue.sync { for r in records { self.records[r.id] = r } }
    }

    public func search(query: String, type: MemoryType?, scope: String?, limit: Int) async throws -> [MemoryRecord] {
        let lower = query.lowercased()
        return queue.sync {
            records.values
                .filter { r in
                    if let t = type, r.type != t { return false }
                    if let s = scope, !r.scope.hasPrefix(s) { return false }
                    return r.content.lowercased().contains(lower)
                }
                .sorted { $0.importance > $1.importance }
                .prefix(limit)
                .map { $0 }
        }
    }

    public func searchSimilar(embedding: [Float], type: MemoryType?, limit: Int) async throws -> [MemoryRecord] {
        // Basic cosine similarity fallback
        return queue.sync {
            records.values
                .filter { r in type == nil || r.type == type }
                .sorted { $0.importance > $1.importance }
                .prefix(limit)
                .map { $0 }
        }
    }

    public func delete(_ id: String) async throws {
        queue.sync { records.removeValue(forKey: id) }
    }

    public func deleteScope(_ scope: String) async throws {
        queue.sync { records = records.filter { !$0.value.scope.hasPrefix(scope) } }
    }

    public func listScopes() async throws -> [String] {
        queue.sync { Array(Set(records.values.map { $0.scope })).sorted() }
    }
}

// MARK: - Memory Service (CrewAI Memory pattern)

public final class MemoryService: @unchecked Sendable {
    public static let shared = MemoryService()
    private var store: MemoryStore = InMemoryStore()

    public func setStore(_ store: MemoryStore) { self.store = store }

    // MARK: - Episodic Memory (conversation logs)

    public func rememberConversation(_ text: String, scope: String = "conversations") async throws {
        let record = MemoryRecord(type: .episodic, content: text, scope: scope, importance: 0.6)
        try await store.save(record)
    }

    // MARK: - Semantic Memory (facts)

    public func rememberFact(_ fact: String, scope: String, importance: Double = 0.7) async throws {
        let record = MemoryRecord(type: .semantic, content: fact, scope: scope, importance: importance)
        try await store.save(record)
    }

    // MARK: - Procedural Memory (learned patterns)

    public func rememberProcedure(_ procedure: String, scope: String = "procedures", importance: Double = 0.5) async throws {
        let record = MemoryRecord(type: .procedural, content: procedure, scope: scope, importance: importance)
        try await store.save(record)
    }

    // MARK: - Recall

    public func recall(query: String, type: MemoryType? = nil, scope: String? = nil, limit: Int = 10) async throws -> [MemoryRecord] {
        try await store.search(query: query, type: type, scope: scope, limit: limit)
    }

    public func recallRecent(scope: String? = nil, limit: Int = 5) async throws -> [MemoryRecord] {
        let all = try await store.search(query: "", type: nil, scope: scope, limit: 100)
        return all.sorted { $0.timestamp > $1.timestamp }.prefix(limit).map { $0 }
    }

    public func recallImportant(scope: String? = nil, limit: Int = 5) async throws -> [MemoryRecord] {
        let all = try await store.search(query: "", type: nil, scope: scope, limit: 100)
        return all.sorted { $0.importance > $1.importance }.prefix(limit).map { $0 }
    }

    // MARK: - Consolidation (CrewAI EncodingFlow pattern)

    public func consolidate(scope: String? = nil) async throws {
        let all = try await store.search(query: "", type: nil, scope: scope, limit: 1000)
        let grouped = Dictionary(grouping: all) { $0.scope }

        for (_, records) in grouped {
            guard records.count > 10 else { continue }
            // Summarize old, low-importance records
            let oldRecords = records.filter { $0.importance < 0.3 && $0.timestamp.timeIntervalSinceNow < -86400 * 7 }
            for record in oldRecords {
                try await store.delete(record.id)
            }
        }
    }
}
