import Foundation

/// Reads session data from Claude Code's JSONL files under ~/.claude/projects/
/// Each .jsonl file is one session.  Lines are JSON objects with a "type" field
/// ("user", "assistant", etc.) and a "timestamp" field.
final class ClaudeSessionReader: SourceReader {

    // MARK: - SourceReader conformance

    let sourceName = "claude_code"

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: projectsDir.path)
    }

    // MARK: - Internals

    private let projectsDir: URL
    private let fileManager = FileManager.default
    private let maxSessions = 100

    /// Initialise with an explicit base directory (defaults to ~/.claude/projects).
    init(projectsDir: URL? = nil) {
        self.projectsDir = projectsDir
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects")
    }

    func listSessions() throws -> [UnifiedSession] {
        guard isAvailable else { return [] }

        var jsonlFiles: [URL] = []
        if let enumerator = fileManager.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                if url.pathExtension == "jsonl" {
                    jsonlFiles.append(url)
                }
            }
        }

        // Sort by modification date, newest first
        jsonlFiles.sort { a, b in
            let dateA = (try? a.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let dateB = (try? b.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return dateA > dateB
        }

        // Cap at 100
        if jsonlFiles.count > maxSessions {
            jsonlFiles = Array(jsonlFiles.prefix(maxSessions))
        }

        return jsonlFiles.compactMap { url -> UnifiedSession? in
            parseSession(url: url)
        }
    }

    // MARK: - SourceReader — load messages

    func loadMessages(forSessionId id: String) throws -> [SessionMessage] {
        // id format: "claude_code:<stableId>"
        // Strip prefix to get stableId, then find the matching JSONL file
        let stableId: String
        if id.hasPrefix("claude_code:") {
            stableId = String(id.dropFirst("claude_code:".count))
        } else {
            stableId = id
        }

        // Search for the file whose name or sessionId matches
        guard let fileURL = findSessionFile(stableId: stableId) else {
            return []
        }

        guard let data = try? Data(contentsOf: fileURL) else { return [] }

        var messages: [SessionMessage] = []
        let isoFormatter = ISO8601DateFormatter()

        data.split(separator: UInt8(ascii: "\n")).forEach { lineData in
            guard let lineObj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { return }
            let type = lineObj["type"] as? String ?? ""

            // Only include user and assistant messages
            guard type == "user" || type == "assistant" else { return }

            var content: String?
            if let msg = lineObj["message"] as? [String: Any],
               let c = msg["content"] as? String {
                content = c
            } else if let c = lineObj["content"] as? String {
                content = c
            }
            guard let c = content else { return }

            let role: SessionMessageRole = (type == "user") ? .user : .assistant
            let ts: SessionTimestamp? = (lineObj["timestamp"] as? String).flatMap { str in
                isoFormatter.date(from: str).map { .unixSeconds($0.timeIntervalSince1970) }
            }
            messages.append(SessionMessage(
                id: UUID().uuidString,
                role: role,
                content: c,
                timestamp: ts
            ))
        }

        return messages
    }

    /// Find the JSONL file for a session by its stable ID.
    private func findSessionFile(stableId: String) -> URL? {
        // Walk the projects dir and find a JSONL file whose name matches or
        // whose sessionId field matches the stableId.
        guard let enumerator = fileManager.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        // Quick check: does a file with this stem exist?
        for case let url as URL in enumerator {
            if url.pathExtension == "jsonl",
               url.deletingPathExtension().lastPathComponent == stableId {
                return url
            }
        }

        // Fall back: re-scan and check sessionId inside each file
        guard let enumerator2 = fileManager.enumerator(
            at: projectsDir,
            includingPropertiesForKeys: [],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for case let url as URL in enumerator2 {
            guard url.pathExtension == "jsonl" else { continue }
            guard let data = try? Data(contentsOf: url) else { continue }
            // Only check first ~20 lines for sessionId
            var lineCount = 0
            for lineData in data.split(separator: UInt8(ascii: "\n")) {
                lineCount += 1
                if lineCount > 20 { break }
                guard let lineObj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }
                if let sid = lineObj["sessionId"] as? String, sid == stableId {
                    return url
                }
            }
        }

        return nil
    }

    // MARK: - Parsing

    private func parseSession(url: URL) -> UnifiedSession? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        var sessionId: String?
        var firstUserMessage: String?
        var messageCount = 0
        var workspace: String?
        var firstTimestamp: Date?
        var lastTimestamp: Date?

        // Parse line-by-line
        data.split(separator: UInt8(ascii: "\n")).forEach { lineData in
            guard let lineObj = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { return }

            let type = lineObj["type"] as? String ?? ""

            // Session ID & workspace from first meaningful line
            if sessionId == nil {
                if let sid = lineObj["sessionId"] as? String, !sid.isEmpty {
                    sessionId = sid
                }
            }
            if workspace == nil {
                if let cwd = lineObj["cwd"] as? String, !cwd.isEmpty {
                    workspace = cwd
                }
            }

            // Timestamps
            if let tsStr = lineObj["timestamp"] as? String,
               let ts = ISO8601DateFormatter().date(from: tsStr) {
                if firstTimestamp == nil { firstTimestamp = ts }
                lastTimestamp = ts
            }

            // Count user/assistant messages and extract first user message
            if type == "user" || type == "assistant" {
                messageCount += 1
            }

            if type == "user" && firstUserMessage == nil {
                if let msg = lineObj["message"] as? [String: Any],
                   let content = msg["content"] as? String {
                    firstUserMessage = String(content.prefix(64))
                } else if let content = lineObj["content"] as? String {
                    firstUserMessage = String(content.prefix(64))
                }
            }
        }

        // Derive a stable ID: use the file stem or sessionId
        let stableId = sessionId ?? url.deletingPathExtension().lastPathComponent

        // Relative path from projects dir
        let indexPath = url.path.replacingOccurrences(
            of: projectsDir.path + "/",
            with: ""
        )

        // File modification date as updatedAt fallback
        let fileModDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        return UnifiedSession(
            id: "claude_code:\(stableId)",
            source: sourceName,
            title: firstUserMessage,
            startedAt: firstTimestamp,
            updatedAt: lastTimestamp ?? fileModDate,
            messageCount: messageCount > 0 ? messageCount : nil,
            workspace: workspace,
            indexPath: indexPath
        )
    }
}