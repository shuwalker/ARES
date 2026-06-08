import ARESCore
import Foundation
import SQLite3

// MARK: - JROS-Compatible SQLite MemoryStore
//
// Persists memories to a SQLite database using the exact schema of JROS (jaeger_os).
// This makes ARES natively compatible with any JROS agent's state.db.
//
// Schema Version: 1
// Tables: schema_version, facts, episodic, episodic_embeddings, schedules, sessions, tool_calls, audit_log

public final class SQLiteMemoryStore: MemoryStore, @unchecked Sendable {
    private let db: OpaquePointer?
    public let dbPath: String
    private let lock = UnsafeMutablePointer<os_unfair_lock>.allocate(capacity: 1)
    public var embedder: OllamaGatewayProvider?

    public let capabilities: Set<String> = ["persistence", "search", "jros-compatible", "embeddings"]

    // MARK: - Init (synchronous — opens DB and creates JROS schema)

    public init(path: String, embedder: OllamaGatewayProvider? = nil) throws {
        self.dbPath = path
        self.embedder = embedder
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
        try Self.executeStatic(db, "PRAGMA synchronous=NORMAL")
        try Self.executeStatic(db, "PRAGMA foreign_keys=ON")
        try Self.executeStatic(db, "PRAGMA busy_timeout=5000")
        
        // Create JROS schema
        try createSchema()
    }

    deinit {
        sqlite3_close(db)
        lock.deallocate()
    }

    // MARK: - JROS Schema Definition

    private func createSchema() throws {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS schema_version (
                id        INTEGER PRIMARY KEY CHECK (id = 1),
                version   INTEGER NOT NULL,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS facts (
                key        TEXT PRIMARY KEY,
                value      TEXT NOT NULL,
                category   TEXT NOT NULL DEFAULT 'general',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_facts_category ON facts (category)",
            """
            CREATE TABLE IF NOT EXISTS episodic (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                session_key     TEXT NOT NULL,
                ts              TEXT NOT NULL,
                user            TEXT,
                answer          TEXT,
                decision_raw    TEXT,
                tool_activity   TEXT,
                latency_ms      INTEGER,
                first_decision  TEXT,
                skipped_final   INTEGER NOT NULL DEFAULT 0,
                meta_json       TEXT
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_episodic_session ON episodic (session_key, id)",
            "CREATE INDEX IF NOT EXISTS idx_episodic_ts ON episodic (ts)",
            """
            CREATE TABLE IF NOT EXISTS episodic_embeddings (
                episodic_id INTEGER PRIMARY KEY
                            REFERENCES episodic(id) ON DELETE CASCADE,
                model       TEXT NOT NULL,
                dim         INTEGER NOT NULL,
                vector      BLOB NOT NULL
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS schedules (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                schedule_id     TEXT UNIQUE NOT NULL,
                cron            TEXT NOT NULL,
                prompt          TEXT NOT NULL,
                next_fire_at    TEXT,
                status          TEXT NOT NULL DEFAULT 'active',
                session_key     TEXT,
                created_at      TEXT NOT NULL,
                last_fired_at   TEXT
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_schedules_status ON schedules (status, next_fire_at)",
            """
            CREATE TABLE IF NOT EXISTS sessions (
                session_key  TEXT PRIMARY KEY,
                started_at   TEXT NOT NULL,
                ended_at     TEXT,
                turn_count   INTEGER NOT NULL DEFAULT 0
            )
            """,
            """
            CREATE TABLE IF NOT EXISTS tool_calls (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                episodic_id   INTEGER REFERENCES episodic(id) ON DELETE SET NULL,
                session_key   TEXT NOT NULL,
                tool_name     TEXT NOT NULL,
                args_json     TEXT,
                result_json   TEXT,
                ok            INTEGER NOT NULL DEFAULT 1,
                error         TEXT,
                elapsed_s     REAL,
                ts            TEXT NOT NULL
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_tool_calls_session ON tool_calls (session_key, id)",
            "CREATE INDEX IF NOT EXISTS idx_tool_calls_tool ON tool_calls (tool_name, ts)",
            """
            CREATE TABLE IF NOT EXISTS audit_log (
                id            INTEGER PRIMARY KEY AUTOINCREMENT,
                ts            TEXT NOT NULL,
                event         TEXT NOT NULL,
                payload_json  TEXT NOT NULL,
                session_key   TEXT
            )
            """,
            "CREATE INDEX IF NOT EXISTS idx_audit_event ON audit_log (event, ts)",
            "CREATE INDEX IF NOT EXISTS idx_audit_ts ON audit_log (ts)"
        ]

        try withDatabaseLock {
            try Self.executeStatic(db, "BEGIN IMMEDIATE")
            do {
                for statement in statements {
                    try Self.executeStatic(db, statement)
                }
                
                // Ensure schema_version is set to 1
                var checkStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, "SELECT version FROM schema_version WHERE id = 1", -1, &checkStmt, nil) == SQLITE_OK {
                    if sqlite3_step(checkStmt) != SQLITE_ROW {
                        let now = ISO8601DateFormatter().string(from: Date())
                        try Self.executeStatic(db, "INSERT INTO schema_version (id, version, created_at, updated_at) VALUES (1, 1, '\(now)', '\(now)')")
                    }
                    sqlite3_finalize(checkStmt)
                }
                
                try Self.executeStatic(db, "COMMIT")
            } catch {
                try Self.executeStatic(db, "ROLLBACK")
                throw error
            }
        }
    }

    // MARK: - MemoryStore Protocol (Mapped to JROS `facts` table)

    public func store(_ memory: Memory) async throws -> String {
        // Generate embedding if an embedder is available
        var memoryToStore = memory
        if embedder != nil && memory.embedding == nil {
            if let newEmbedding = try? await embedder?.generateEmbeddings(prompt: memory.content) {
                memoryToStore = Memory(
                    id: memory.id,
                    content: memory.content,
                    context: memory.context,
                    timestamp: memory.timestamp,
                    embedding: newEmbedding
                )
            }
        }
        
        return try withDatabaseLock {
            let key = memoryToStore.id
            let value = memoryToStore.content
            
            // Extract category if available, otherwise 'general'
            var category = "general"
            if case .string(let c) = memoryToStore.context["category"] {
                category = c.lowercased()
            }
            
            let now = ISO8601DateFormatter().string(from: memoryToStore.timestamp)

            var stmt: OpaquePointer?
            let sql = """
            INSERT OR REPLACE INTO facts (key, value, category, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?)
            """

            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw MemoryStoreError.queryFailed("Prepare failed for store: \(Self.errorMessage(db))")
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, key, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, value, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, category, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 4, now, -1, SQLITE_TRANSIENT) // created_at
            sqlite3_bind_text(stmt, 5, now, -1, SQLITE_TRANSIENT) // updated_at

            let step = sqlite3_step(stmt)
            guard step == SQLITE_DONE else {
                throw MemoryStoreError.queryFailed("Store failed: \(Self.errorMessage(db))")
            }

            print("✅ [MEMORY] Stored fact: \(key) '\(value.prefix(40))...'")
            return key
        }
    }

    public func retrieve(query: String, limit: Int) async throws -> [Memory] {
        try withDatabaseLock {
            var results: [Memory] = []

            // Search JROS `facts` table
            let memSQL = """
            SELECT key, value, category, created_at, updated_at
            FROM facts
            WHERE value LIKE ? OR key LIKE ?
            ORDER BY updated_at DESC
            LIMIT ?
            """

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, memSQL, -1, &stmt, nil) == SQLITE_OK else {
                throw MemoryStoreError.queryFailed("Prepare failed for retrieve: \(Self.errorMessage(db))")
            }
            defer { sqlite3_finalize(stmt) }

            let pattern = "%\(query)%"
            sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, pattern, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(limit))

            let formatter = ISO8601DateFormatter()
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = String(cString: sqlite3_column_text(stmt, 0))
                let content = String(cString: sqlite3_column_text(stmt, 1))
                let category = String(cString: sqlite3_column_text(stmt, 2))
                let createdStr = String(cString: sqlite3_column_text(stmt, 3))
                
                let timestamp = formatter.date(from: createdStr) ?? Date()

                results.append(Memory(
                    id: id,
                    content: content,
                    context: ["category": .string(category)],
                    timestamp: timestamp,
                    embedding: nil
                ))
            }

            // Also search JROS `episodic` table (chat history)
            if results.count < limit {
                let chatSQL = """
                SELECT id, user, answer, ts
                FROM episodic
                WHERE user LIKE ? OR answer LIKE ?
                ORDER BY id DESC
                LIMIT ?
                """

                var chatStmt: OpaquePointer?
                if sqlite3_prepare_v2(db, chatSQL, -1, &chatStmt, nil) == SQLITE_OK {
                    defer { sqlite3_finalize(chatStmt) }

                    sqlite3_bind_text(chatStmt, 1, pattern, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_text(chatStmt, 2, pattern, -1, SQLITE_TRANSIENT)
                    sqlite3_bind_int(chatStmt, 3, Int32(limit - results.count))

                    while sqlite3_step(chatStmt) == SQLITE_ROW {
                        let id = Int(sqlite3_column_int64(chatStmt, 0))
                        
                        var contentParts: [String] = []
                        if let cUser = sqlite3_column_text(chatStmt, 1) {
                            contentParts.append("USER: \(String(cString: cUser))")
                        }
                        if let cAnswer = sqlite3_column_text(chatStmt, 2) {
                            contentParts.append("ASSISTANT: \(String(cString: cAnswer))")
                        }
                        
                        let tsStr = String(cString: sqlite3_column_text(chatStmt, 3))
                        let timestamp = formatter.date(from: tsStr) ?? Date()

                        results.append(Memory(
                            id: "episodic-\(id)",
                            content: contentParts.joined(separator: "\n"),
                            context: ["source": .string("episodic")],
                            timestamp: timestamp,
                            embedding: nil
                        ))
                    }
                }
            }

            print("🔍 [MEMORY] Retrieved \(results.count) facts/episodes for '\(query)'")
            return results
        }
    }

    public func update(_ id: String, with updates: [String: AnyCodable]) async throws {
        try withDatabaseLock {
            let fetchSQL = "SELECT created_at FROM facts WHERE key = ?"
            var fetchStmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, fetchSQL, -1, &fetchStmt, nil) == SQLITE_OK else {
                throw MemoryStoreError.queryFailed("Prepare failed for update fetch: \(Self.errorMessage(db))")
            }
            defer { sqlite3_finalize(fetchStmt) }

            sqlite3_bind_text(fetchStmt, 1, id, -1, SQLITE_TRANSIENT)
            guard sqlite3_step(fetchStmt) == SQLITE_ROW else {
                throw MemoryStoreError.notFound("Fact \(id) not found")
            }

            // Only 'value' and 'category' are modifiable for facts
            let newContent: String?
            if case .string(let s) = updates["content"] {
                newContent = s
            } else {
                newContent = nil
            }
            
            var newCategory: String?
            if case .string(let c) = updates["category"] {
                newCategory = c
            }

            guard newContent != nil || newCategory != nil else { return }
            
            let now = ISO8601DateFormatter().string(from: Date())

            if let content = newContent, let category = newCategory {
                let updateSQL = "UPDATE facts SET value = ?, category = ?, updated_at = ? WHERE key = ?"
                var updateStmt: OpaquePointer?
                sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil)
                defer { sqlite3_finalize(updateStmt) }
                sqlite3_bind_text(updateStmt, 1, content, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(updateStmt, 2, category, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(updateStmt, 3, now, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(updateStmt, 4, id, -1, SQLITE_TRANSIENT)
                sqlite3_step(updateStmt)
            } else if let content = newContent {
                let updateSQL = "UPDATE facts SET value = ?, updated_at = ? WHERE key = ?"
                var updateStmt: OpaquePointer?
                sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil)
                defer { sqlite3_finalize(updateStmt) }
                sqlite3_bind_text(updateStmt, 1, content, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(updateStmt, 2, now, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(updateStmt, 3, id, -1, SQLITE_TRANSIENT)
                sqlite3_step(updateStmt)
            } else if let category = newCategory {
                let updateSQL = "UPDATE facts SET category = ?, updated_at = ? WHERE key = ?"
                var updateStmt: OpaquePointer?
                sqlite3_prepare_v2(db, updateSQL, -1, &updateStmt, nil)
                defer { sqlite3_finalize(updateStmt) }
                sqlite3_bind_text(updateStmt, 1, category, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(updateStmt, 2, now, -1, SQLITE_TRANSIENT)
                sqlite3_bind_text(updateStmt, 3, id, -1, SQLITE_TRANSIENT)
                sqlite3_step(updateStmt)
            }

            print("✏️ [MEMORY] Updated fact: \(id)")
        }
    }

    public func delete(_ id: String) async throws {
        try withDatabaseLock {
            let sql = "DELETE FROM facts WHERE key = ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw MemoryStoreError.queryFailed("Prepare failed for delete: \(Self.errorMessage(db))")
            }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
            sqlite3_step(stmt)

            let changes = sqlite3_changes(db)
            guard changes > 0 else {
                throw MemoryStoreError.notFound("Fact \(id) not found")
            }

            print("🗑️ [MEMORY] Deleted fact: \(id)")
        }
    }

    // MARK: - JROS Episodic Append

    /// Appends a chat turn directly to the `episodic` table (JROS compatible).
    public func appendEpisodic(sessionKey: String, user: String?, answer: String?) throws {
        try withDatabaseLock {
            let now = ISO8601DateFormatter().string(from: Date())
            let sql = """
            INSERT INTO episodic (session_key, ts, user, answer, skipped_final)
            VALUES (?, ?, ?, ?, 0)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
                throw MemoryStoreError.queryFailed("Prepare failed for appendEpisodic")
            }
            defer { sqlite3_finalize(stmt) }
            
            sqlite3_bind_text(stmt, 1, sessionKey, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, now, -1, SQLITE_TRANSIENT)
            
            if let user {
                sqlite3_bind_text(stmt, 3, user, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 3)
            }
            
            if let answer {
                sqlite3_bind_text(stmt, 4, answer, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            
            sqlite3_step(stmt)
        }
    }

    // MARK: - Helpers

    private func withDatabaseLock<T>(_ body: () throws -> T) rethrows -> T {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return try body()
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

private let SQLITE_TRANSIENT: sqlite3_destructor_type = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

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
