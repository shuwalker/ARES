import Foundation

/// MemoryStore protocol: persistent episodic and semantic memory.
/// Conforming types: SQLiteMemoryStore, InMemoryMemoryStore, VectorMemoryStore
public protocol MemoryStore: AnyObject, Sendable {
    /// Store a memory. Assigns UUID if not provided.
    /// Returns the memory's ID.
    func store(_ memory: Memory) async throws -> String

    /// Retrieve memories by semantic search query.
    /// Uses vector embedding if available; falls back to text matching.
    func retrieve(query: String, limit: Int) async throws -> [Memory]

    /// Update a memory by ID. Only specified fields are changed.
    func update(_ id: String, with updates: [String: AnyCodable]) async throws

    /// Delete a memory by ID.
    func delete(_ id: String) async throws

    /// What can this memory store do?
    /// Examples: ["vectorSearch", "persistence", "iCloud", "llmEmbedding"]
    var capabilities: Set<String> { get }
}

/// A single memory: content + context + embedding.
public struct Memory: Codable, Sendable, Equatable {
    public let id: String
    public let content: String                      // The actual memory text
    public let context: [String: AnyCodable]        // Metadata: who, where, when, tags, etc.
    public let timestamp: Date
    public let embedding: [Double]?                 // Optional; backend can compute

    public init(
        id: String = UUID().uuidString,
        content: String,
        context: [String: AnyCodable] = [:],
        timestamp: Date = Date(),
        embedding: [Double]? = nil
    ) {
        self.id = id
        self.content = content
        self.context = context
        self.timestamp = timestamp
        self.embedding = embedding
    }
}
