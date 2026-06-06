import Foundation

/// Reads session data from Odysseus's SQLite database.
/// Uses the system `sqlite3` binary via Process to query the DB — no Swift
/// SQLite dependency required.
final class OdysseusSessionReader: SourceReader {

    // MARK: - SourceReader conformance

    let sourceName = "odysseus"

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: dbPath.path)
    }

    // MARK: - Internals

    private let dbPath: URL
    private let maxSessions = 100

    /// Initialise with an explicit DB path (defaults to ~/GitHub/odysseus/data/app.db).
    init(dbPath: URL? = nil) {
        self.dbPath = dbPath
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("GitHub/odysseus/data/app.db")
    }

    func listSessions() throws -> [UnifiedSession] {
        guard isAvailable else { return [] }

        // Query sessions table — Odysseus schema:
        //   id, name, model, owner, archived, folder, last_accessed, last_message_at,
        //   message_count, created_at, updated_at
        let sql = """
        SELECT id, name, model, created_at, updated_at, last_message_at, message_count, folder
        FROM sessions
        ORDER BY updated_at DESC
        LIMIT \(maxSessions)
        """

        let rawOutput = runSQLite(sql)
        guard !rawOutput.isEmpty else { return [] }

        // Parse pipe-delimited output
        var sessions: [UnifiedSession] = []
        for line in rawOutput.components(separatedBy: "\n") where !line.isEmpty {
            let fields = line.components(separatedBy: "|")
            guard fields.count >= 8 else { continue }

            let id = fields[0]
            let name = fields[1].isEmpty ? nil : String(fields[1].prefix(64))
            let createdAt = parseDateString(fields[3])
            let updatedAt = parseDateString(fields[4])
            let lastMsgAt = parseDateString(fields[5])
            var messageCount: Int?
            if let mc = Int(fields[6]), mc > 0 {
                messageCount = mc
            }
            let folder = fields[7].isEmpty ? nil : fields[7]

            // Use the most recent date as updatedAt
            let effectiveUpdated = [updatedAt, lastMsgAt]
                .compactMap { $0 }
                .max() ?? updatedAt

            sessions.append(UnifiedSession(
                id: "odysseus:\(id)",
                source: sourceName,
                title: name,
                startedAt: createdAt,
                updatedAt: effectiveUpdated,
                messageCount: messageCount,
                workspace: folder,
                indexPath: "app.db/sessions/\(id)"
            ))
        }

        return sessions
    }

    // MARK: - SourceReader — load messages

    /// Loads messages from an Odysseus session by querying the SQLite DB.
    func loadMessages(forSessionId id: String) throws -> [SessionMessage] {
        // id format: "odysseus:<uuid>"
        let odysseusId: String
        if id.hasPrefix("odysseus:") {
            odysseusId = String(id.dropFirst("odysseus:".count))
        } else {
            odysseusId = id
        }

        guard isAvailable else { return [] }

        // Query messages from the messages table.
        // Odysseus schema: messages(id, session_id, role, content, created_at)
        let sql = """
        SELECT role, content, created_at
        FROM messages
        WHERE session_id = '\(odysseusId)'
        ORDER BY created_at ASC
        LIMIT 100
        """

        let rawOutput = runSQLite(sql)
        guard !rawOutput.isEmpty else { return [] }

        var messages: [SessionMessage] = []
        for line in rawOutput.components(separatedBy: "\n") where !line.isEmpty {
            let fields = line.components(separatedBy: "|")
            guard fields.count >= 2 else { continue }

            let roleStr = fields[0]
            let content = fields[1]
            let role: SessionMessageRole = (roleStr == "user") ? .user : .assistant
            let ts: SessionTimestamp?
            if fields.count >= 3, let date = parseDateString(fields[2]) {
                ts = .unixSeconds(date.timeIntervalSince1970)
            } else {
                ts = nil
            }
            messages.append(SessionMessage(
                id: UUID().uuidString,
                role: role,
                content: content,
                timestamp: ts
            ))
        }

        return messages
    }

    // MARK: - SQLite via Process

    private func runSQLite(_ sql: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [
            dbPath.path,
            "-separator", "|",
            sql
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ""
        }

        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let output = String(data: data, encoding: .utf8) else {
            return ""
        }

        return output
    }

    // MARK: - Date parsing

    /// Odysseus stores dates as ISO 8601 strings (e.g. "2026-06-02 07:42:42.540709")
    private func parseDateString(_ s: String) -> Date? {
        guard !s.isEmpty else { return nil }

        // Try ISO 8601 first
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }

        // Fallback: "2026-06-02 07:42:42.540709" (Odysseus format)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        if let d = fmt.date(from: s) { return d }

        // Try without fractional seconds
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let d = fmt.date(from: s) { return d }

        return nil
    }
}