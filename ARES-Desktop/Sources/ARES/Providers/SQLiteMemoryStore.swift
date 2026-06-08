import ARESCore
import Foundation
import SQLite3

// MARK: - SQLite-backed MemoryStore
//
// Persists memories to a SQLite database using the C API (no GRDB dependency).
// The database file is created/opened at init. A `ares_memories` table is ensured.
//
// For the ARES companion, the default path can point at the odysseus app.db
// which has a `chat_messages` table. Memories are stored in a separate
// `ares_memories` table within the same database so they coexist with
// the existing schema.

public final class SQLiteMemoryStore: MemoryStore, @unchecked Sendable {
    private let db: OpaquePointer?
    private let dbPath: String
    private let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)

    public let capabilities: Set<String> = ["persistence", "search"]

    // MARK: - Init (synchronous — opens DB and creates schema)

    public init(path: String) throws {
        self.dbPath = path
        self.lock.initialize(to: os_unfair_lock())

        // Expand tilde
        let expandedPath = NSString(string: path).expandingTildeInPath

        // Ensure parent directory exists
        let dir = NSString(string: expandedPath).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Open database
        var handle: OpaquePointer?
        let result = sqlite3_open(expandedPath, &handle)
        if result != SQLITE_OK {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            throw MemoryStoreError.openFailed("Cannot open database at \(path): \(msg)")
        }
        self.db = handle

        // Enable WAL mode for concurrent reads
        try Self.executeStatic(db, "PRAGMA journal_mode=WAL")
        // Create ARES memories table
        try createSchema()
    }

    deinit {
        sqlite3_close(db)
        lock.deallocate()
    }

    // MARK: - Schema

    private func createSchema() throws {
        try Self.executeStatic(db, """
        CREATE TABLE IF NOT EXISTS ares_memories (
            id TEXT PRIMARY KEY,
            content TEXT NOT NULL,
            context_json TEXT NOT NULL DEFAULT '{}',
            timestamp REAL NOT NULL,
            embedding_blob BLOB
        )
        """)
        try Self.executeStatic(db, """
        CREATE INDEX IF NOT EXISTS idx_ares_mem_timestamp ON ares_memories(timestamp DESC)
        """)
        try Self.executeStatic(db, """
        CREATE INDEX IF NOT EXISTS idx_ares_mem_content ON ares_memories(content)
        """)
    }

    // MARK: - MemoryStore Protocol

    public func store(_ memory: Memory) async throws -> String {
        try withDatabaseLock {
            let id = memory.id
            let content = memory.content
            let contextData = try JSONEncoder().encode(memory.context)
            let contextJSON = String(data: contextData, encoding: .utf8) ?? "{}"
            let timestamp = memory.timestamp.timeIntervalSince1970
            let embeddingData = memory.embedding.flatMap { try? JSONEncoder().encode($0) }

            var stmt: OpaquePointer?
            let sql = """
            INSERT OR REPLACE INTO ares_memories (id, content, context_json, timestamp, embedding_blob)
            VALUES (?, ?, ?, ?, ?)
            """

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw MemoryStoreError.queryFailed("Prepare failed for store: \(Self.errorMessage(db))")
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, content, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, contextJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 4, timestamp)

            if let embeddingData {
                _ = embeddingData.withUnsafeBytes { ptr in
                    sqlite3_bind_blob(stmt, 5, ptr.baseAddress, Int32(embeddingData.count), SQLITE_TRANSIENT)
                }
            } else {
                sqlite3_bind_null(stmt, 5)
            }

            let step = sqlite3_step(stmt)
            guard step == SQLITE_DONE else {
                throw MemoryStoreError.queryFailed("Store failed: \(Self.errorMessage(db))")
            }

            print("✅ [MEMORY] Stored memory: \(id) '\(content.prefix(40))...'")
            return id
        }
    }

    public func retrieve(query: String, limit: Int) async throws -> [Memory] {
        try withDatabaseLock {
            var results: [Memory] = []

            // 1. Search ares_memories
            let memSQL = """
            SELECT id, content, context_json, timestamp, embedding_blob
            FROM ares_memories
            WHERE content LIKE ?
            ORDER BY timestamp DESC
            LIMIT ?
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, memSQL, -1, &stmt, nil) == SQLITE_OK else {
                throw MemoryStoreError.queryFailed("Prepare failed for retrieve: \(Self.errorMessage(db))")
            }
            defer { sqlite3_finalize(stmt) }

            let pattern = "%\(query)%"
            sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 2, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let memory = Self.parseRow(stmt) {
                    results.append(memory)
                }
            }

            // 2. Also search chat_messages if it exists (read-only, for context)
            if results.count < limit {
                let chatSQL = """
                SELECT id, content, timestamp
                FROM chat_messages
                WHERE content LIKE ?
                ORDER BY timestamp DESC
                LIMIT ?
                """

                var chatStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, chatSQL, -1, &chatStmt, nil) == SQLITE_OK {
                    defer { sqlite3_finalize(chatStmt) }

                    sqlite3_bind_text(chatStmt, 1, pattern, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int(chatStmt, 2, Int32(limit - results.count))

                    while sqlite3_step(chatStmt) == SQLITE_ROW {
                        let id = String(cString: sqlite3_column_text(chatStmt, 0))
                        let content = String(cString: sqlite3_column_text(chatStmt, 1))
                        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(chatStmt, 2))

                        results.append(Memory(
                            id: id,
                            content: content,
                            context: ["source": AnyCodable.string("chat_messages")],
                            timestamp: timestamp,
                            embedding: nil
                        ))
                    }
                }
                // If chat_messages doesn't exist, that's fine — we just skip it
            }

            print("🔍 [MEMORY] Retrieved \(results.count) memories for '\(query)'")
            return results
        }
    }

    public func update(_ id: String, with updates: [String: AnyCodable]) async throws {
        try withDatabaseLock {
            // First fetch existing memory
            let fetchSQL = "SELECT content, context_json, timestamp, embedding_blob FROM ares_memories WHERE id = ?"
            var fetchStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, fetchSQL, -1, &fetchStmt, nil) == SQLITE_OK else {
                throw MemoryStoreError.queryFailed("Prepare failed for update fetch: \(Self.errorMessage(db))")
            }
            defer { sqlite3_finalize(fetchStmt) }

            sqlite3_bind_text(fetchStmt, 1, id, -1, SQLITE_TRANSIENT)

            guard sqlite3_step(fetchStmt) == SQLITE_ROW else {
                throw MemoryStoreError.notFound("Memory \(id) not found")
            }

            let existingContent = String(cString: sqlite3_column_text(fetchStmt, 0))
            let existingContextJSON = String(cString: sqlite3_column_text(fetchStmt, 1))
            let existingTimestamp = sqlite3_column_double(fetchStmt, 2)

            // Decode existing context and merge updates
            var context: [String: AnyCodable] = [:]
            if let data = existingContextJSON.data(using: .utf8),
               let decoded = try? JSONDecoder().decode([String: AnyCodable].self, from: data) {
                context = decoded
            }
            for (key, value) in updates {
                context[key] = value
            }

            // Determine new content if "content" key present in updates
            let newContent: String
            if case .string(let s) = updates["content"] {
                newContent = s
            } else {
                newContent = existingContent
            }

            let contextData = try JSONEncoder().encode(context)
            let contextJSON = String(data: contextData, encoding: .utf8) ?? "{}"

            // Update row
            let updateSQL = """
            UPDATE ares_memories SET content = ?, context_json = ?, timestamp = ? WHERE id = ?
            """
            var updateStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil) == SQLITE_OK else {
                throw MemoryStoreError.queryFailed("Prepare failed for update: \(Self.errorMessage(db))")
            }
            defer { sqlite3_finalize(updateStmt) }

            sqlite3_bind_text(updateStmt, 1, newContent, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(updateStmt, 2, contextJSON, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(updateStmt, 3, existingTimestamp)
            sqlite3_bind_text(updateStmt, 4, id, -1, SQLITE_TRANSIENT)

            let step = sqlite3_step(updateStmt)
            guard step == SQLITE_DONE else {
                throw MemoryStoreError.queryFailed("Update failed: \(Self.errorMessage(db))")
            }

            print("✏️ [MEMORY] Updated memory: \(id)")
        }
    }

    public func delete(_ id: String) async throws {
        try withDatabaseLock {
            let sql = "DELETE FROM ares_memories WHERE id = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw MemoryStoreError.queryFailed("Prepare failed for delete: \(Self.errorMessage(db))")
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)

            let step = sqlite3_step(stmt)
            guard step == SQLITE_DONE else {
                throw MemoryStoreError.queryFailed("Delete failed: \(Self.errorMessage(db))")
            }

            let changes = sqlite3_changes(db)
            guard changes > 0 else {
                throw MemoryStoreError.notFound("Memory \(id) not found")
            }

            print("🗑️ [MEMORY] Deleted memory: \(id)")
        }
    }

    // MARK: - Helpers

    private func withDatabaseLock<T>(_ body: () throws -> T) rethrows -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return try body()
    }

    private static func parseRow(_ stmt: OpaquePointer?) -> Memory? {
        guard let stmt else { return nil }

        let id = String(cString: sqlite3_column_text(stmt, 0))
        let content = String(cString: sqlite3_column_text(stmt, 1))
        let contextJSON = String(cString: sqlite3_column_text(stmt, 2))
        let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3))

        var context: [String: AnyCodable] = [:]
        if let data = contextJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: AnyCodable].self, from: data) {
            context = decoded
        }

        var embedding: [Double]? = nil
        if let blobPtr = sqlite3_column_blob(stmt, 4) {
            let blobSize = sqlite3_column_bytes(stmt, 4)
            let embeddingData = Data(bytes: blobPtr, count: Int(blobSize))
            embedding = try? JSONDecoder().decode([Double].self, from: embeddingData)
        }

        return Memory(
            id: id,
            content: content,
            context: context,
            timestamp: timestamp,
            embedding: embedding
        )
    }

    @discardableResult
    private static func executeStatic(_ db: OpaquePointer?, _ sql: String) throws -> Bool {
        var errMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if result != SQLITE_OK {
            let message = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw MemoryStoreError.queryFailed("SQL error: \(message)")
        }
        return true
    }

    private static func errorMessage(_ db: OpaquePointer?) -> String {
        guard let db else { return "nil db" }
        return String(cString: sqlite3_errmsg(db))
    }
}

// SQLITE_TRANSIENT is a C macro that Swift can't see directly.
// It's defined as ((sqlite3_destructor_type)-1) in sqlite3.h
private let SQLITE_TRANSIENT: sqlite3_destructor_type = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Errors

enum MemoryStoreError: Error, Sendable, LocalizedError {
    case openFailed(String)
    case queryFailed(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): return "MemoryStore open failed: \(msg)"
        case .queryFailed(let msg): return "MemoryStore query failed: \(msg)"
        case .notFound(let msg): return "MemoryStore not found: \(msg)"
        }
    }
}
