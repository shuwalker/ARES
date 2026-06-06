import Foundation

// MARK: - Companion Chat Service
// Calls the Hermes CLI (`hermes --yolo chat --quiet --query`) and persists
// each conversation session to ~/.ares/memory/sessions/{id}.json.

struct CompanionChatTurnResult {
    let responseText: String
    let sessionID: String
}

final class CompanionChatService: @unchecked Sendable {

    // MARK: - Singleton
    static let shared = CompanionChatService()

    // MARK: - Session persistence directory
    private let sessionsDirectory: URL

    private init(sessionsDirectory: URL? = nil) {
        let aresDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ares", isDirectory: true)
            .appendingPathComponent("memory", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
        self.sessionsDirectory = sessionsDirectory ?? aresDir
        ensureSessionsDirectory()
    }

    // MARK: - Directory setup

    private func ensureSessionsDirectory() {
        try? FileManager.default.createDirectory(
            at: sessionsDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: Int16(0o700))]
        )
    }

    // MARK: - Send a message via Hermes CLI

    /// Sends a user message to Hermes via the CLI and returns the response.
    /// - Parameters:
    ///   - prompt: The user's message text.
    ///   - sessionID: An optional Hermes session ID to continue an existing conversation.
    ///   - model: Optional Hermes model override (e.g. "gpt-5.5"). When nil, uses the user's config default.
    ///   - provider: Optional Hermes provider override (e.g. "openai-codex"). When nil, uses the user's config default.
    /// - Returns: A `CompanionChatTurnResult` with the response text and session ID.
    func sendMessage(
        _ prompt: String,
        sessionID: String?,
        model: String? = nil,
        provider: String? = nil
    ) async throws -> CompanionChatTurnResult {
        let output = try await runHermesCLI(
            prompt: prompt,
            sessionID: sessionID,
            model: model,
            provider: provider
        )

        // Parse session_id from the first line of output (format: "session_id: <id>")
        let lines = output.components(separatedBy: "\n")
        var parsedSessionID: String?
        var responseLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("session_id:") && parsedSessionID == nil {
                let idPart = trimmed.dropFirst("session_id:".count).trimmingCharacters(in: .whitespaces)
                parsedSessionID = String(idPart)
            } else {
                responseLines.append(line)
            }
        }

        let responseText = responseLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedID = parsedSessionID ?? sessionID ?? UUID().uuidString

        return CompanionChatTurnResult(
            responseText: responseText.isEmpty ? "No response from ARES." : responseText,
            sessionID: resolvedID
        )
    }

    // MARK: - Run Hermes CLI process

    private func runHermesCLI(
        prompt: String,
        sessionID: String?,
        model: String? = nil,
        provider: String? = nil
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/env")

                var arguments = ["hermes", "--yolo"]

                // --model and --provider override the user's config
                if let m = model, !m.isEmpty {
                    arguments += ["-m", m]
                }
                if let p = provider, !p.isEmpty {
                    arguments += ["--provider", p]
                }

                if let sid = sessionID {
                    arguments += ["--resume", sid]
                }

                arguments += ["chat", "--query", prompt]
                process.arguments = arguments

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe
                process.environment = ProcessInfo.processInfo.environment

                // Suppress NO_COLOR for stable output parsing
                var env = ProcessInfo.processInfo.environment
                env["NO_COLOR"] = "1"
                env["TERM"] = "dumb"
                process.environment = env

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()

                let stdoutStr = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderrStr = String(data: stderrData, encoding: .utf8) ?? ""

                if process.terminationStatus != 0 && stdoutStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let error = stderrStr.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: "ARES backend error: \(error.isEmpty ? "exit code \(process.terminationStatus)" : error)")
                    return
                }

                // Combine stdout; stderr only if stdout is empty
                let combined: String
                let trimmedOut = stdoutStr.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedOut.isEmpty {
                    combined = stdoutStr
                } else {
                    combined = stderrStr
                }

                continuation.resume(returning: combined)
            }
        }
    }

    // MARK: - Persist session to disk

    /// Saves (or appends to) a session JSON file at ~/.ares/memory/sessions/{id}.json.
    /// The format matches the hermes-webui Session model shape.
    func persistSession(
        id: String,
        title: String,
        messages: [PersistedChatMessage],
        model: String? = nil
    ) {
        ensureSessionsDirectory()

        let fileURL = sessionsDirectory.appendingPathComponent("\(id).json")

        // Load existing session if present
        var existingMessages: [[String: Any]] = []
        var existingCreatedAt: Double?
        if let data = try? Data(contentsOf: fileURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let msgs = existing["messages"] as? [[String: Any]] {
                existingMessages = msgs
            }
            existingCreatedAt = existing["created_at"] as? Double
        }

        let now = Date().timeIntervalSince1970
        let createdAt = existingCreatedAt ?? now
        let messageCount = existingMessages.count + messages.count

        // Convert new messages to dicts and append
        let newMessageDicts = messages.map { msg -> [String: Any] in
            var dict: [String: Any] = [
                "role": msg.role.rawValue,
                "content": msg.content,
                "timestamp": Int(msg.timestamp.timeIntervalSince1970)
            ]
            // Persist references if present
            if let refs = msg.references, !refs.isEmpty {
                dict["references"] = refs.map { ref -> [String: Any] in
                    var refDict: [String: Any] = [
                        "sessionId": ref.sessionId,
                        "sourceName": ref.sourceName
                    ]
                    if let title = ref.title { refDict["title"] = title }
                    if let ts = ref.timestamp { refDict["timestamp"] = ts.timeIntervalSince1970 }
                    if let snippet = ref.snippet { refDict["snippet"] = snippet }
                    return refDict
                }
            }
            return dict
        }
        let allMessages = existingMessages + newMessageDicts

        var sessionDict: [String: Any] = [
            "session_id": id,
            "title": title,
            "workspace": FileManager.default.homeDirectoryForCurrentUser.path,
            "model": model ?? "hermes",
            "messages": allMessages,
            "message_count": messageCount,
            "created_at": createdAt,
            "updated_at": now,
            "tool_calls": [],
            "source_tag": "ares-companion"
        ]

        let payload: Data
        do {
            payload = try JSONSerialization.data(
                withJSONObject: sessionDict,
                options: [.sortedKeys, .prettyPrinted]
            )
        } catch {
            print("[CompanionChatService] Failed to serialize session: \(error)")
            return
        }

        // Atomic write
        let tmpURL = fileURL.appendingPathExtension("tmp.\(ProcessInfo.processInfo.processIdentifier)")
        do {
            try payload.write(to: tmpURL, options: .atomic)
            try FileManager.default.moveItem(at: tmpURL, to: fileURL)
        } catch {
            // Fallback: non-atomic write
            try? payload.write(to: fileURL, options: .atomic)
            try? FileManager.default.removeItem(at: tmpURL)
        }
    }

    // MARK: - List sessions for history pane

    /// Lightweight summary of a session, used by the history list UI.
    struct SessionSummary: Identifiable {
        let id: String          // session filename stem (used as sessionID)
        let title: String       // first 64 chars of first user message
        let updatedAt: Date
        let messageCount: Int
    }

    /// Returns session summaries sorted newest-first, capped at `limit`.
    func listSessions(limit: Int = 50) -> [SessionSummary] {
        ensureSessionsDirectory()

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return []
        }

        let jsonFiles = contents.filter { $0.pathExtension == "json" }

        // Sort by modification date, newest first
        let sorted = jsonFiles.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return date1 > date2
        }

        var summaries: [SessionSummary] = []
        for url in sorted.prefix(limit) {
            let id = url.deletingPathExtension().lastPathComponent

            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let title = json["title"] as? String ?? id
            let updatedAt = (json["updated_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
                ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey])).flatMap { $0.contentModificationDate }
                ?? Date.distantPast
            let messageCount = json["message_count"] as? Int
                ?? (json["messages"] as? [[String: Any]])?.count
                ?? 0

            summaries.append(SessionSummary(
                id: id,
                title: String(title.prefix(64)),
                updatedAt: updatedAt,
                messageCount: messageCount
            ))
        }

        return summaries
    }

    /// Loads the full message list for a session by id.
    func loadSessionMessages(sessionID: String) -> [ChatBubble]? {
        let fileURL = sessionsDirectory.appendingPathComponent("\(sessionID).json")
        guard let data = try? Data(contentsOf: fileURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let messageDicts = json["messages"] as? [[String: Any]] else {
            return nil
        }

        return messageDicts.compactMap { msg -> ChatBubble? in
            guard let roleStr = msg["role"] as? String,
                  let content = msg["content"] as? String else { return nil }
            let role: BubbleRole = (roleStr == "user") ? .user : .assistant

            // Load references if present
            var references: [AttachedReference]? = nil
            if let refsData = msg["references"] as? [[String: Any]], !refsData.isEmpty {
                references = refsData.compactMap { refDict -> AttachedReference? in
                    guard let sessionId = refDict["sessionId"] as? String,
                          let sourceName = refDict["sourceName"] as? String else { return nil }
                    let title = refDict["title"] as? String
                    let timestamp = (refDict["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) }
                    let snippet = refDict["snippet"] as? String
                    return AttachedReference(
                        sessionId: sessionId,
                        sourceName: sourceName,
                        title: title,
                        timestamp: timestamp,
                        snippet: snippet
                    )
                }
                if references?.isEmpty == true { references = nil }
            }

            return ChatBubble(role: role, content: content, references: references)
        }
    }

    /// Loads the most recent session ID from disk (for session continuity).
    func loadMostRecentSessionID() -> String? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: sessionsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        ) else {
            return nil
        }

        let jsonFiles = contents.filter { $0.pathExtension == "json" }
        guard !jsonFiles.isEmpty else { return nil }

        let sorted = jsonFiles.sorted { url1, url2 in
            let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return date1 > date2
        }

        return sorted.first?.deletingPathExtension().lastPathComponent
    }
}

// MARK: - Persisted message model

enum PersistedChatRole: String, Codable {
    case user
    case assistant
    case system
    case tool
}

struct PersistedChatMessage: Codable {
    let role: PersistedChatRole
    let content: String
    let timestamp: Date
    /// Source references attached to this message (for inline citations)
    var references: [AttachedReference]?
}