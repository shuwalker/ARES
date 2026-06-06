import Foundation

/// Reads session data from Gemini CLI's git-backed history directories.
/// Each subdirectory under ~/.gemini/history/ is a separate project/workspace
/// with its own git repo.  Sessions are represented by git commits.
final class GeminiSessionReader: SourceReader {

    // MARK: - SourceReader conformance

    let sourceName = "gemini"

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: historyDir.path)
    }

    // MARK: - Internals

    private let historyDir: URL
    private let fileManager = FileManager.default
    private let maxSessions = 100

    /// Initialise with an explicit base directory (defaults to ~/.gemini/history).
    init(historyDir: URL? = nil) {
        self.historyDir = historyDir
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".gemini/history")
    }

    func listSessions() throws -> [UnifiedSession] {
        guard isAvailable else { return [] }

        var sessions: [UnifiedSession] = []

        let repoDirs = try fileManager.contentsOfDirectory(
            at: historyDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }

        for repoDir in repoDirs {
            let repoName = repoDir.lastPathComponent
            let projectRoot = loadProjectRoot(repoDir: repoDir)
            let gitLogEntries = readGitLog(repoDir: repoDir)

            for entry in gitLogEntries {
                let stableId = "gemini:\(repoName):\(entry.commit)"
                let indexPath = "\(repoName)/.git"

                // Truncate title to 64 chars
                let title = String(entry.subject.prefix(64))

                sessions.append(UnifiedSession(
                    id: stableId,
                    source: sourceName,
                    title: title.isEmpty ? nil : title,
                    startedAt: entry.date,
                    updatedAt: entry.date,
                    messageCount: nil,
                    workspace: projectRoot,
                    indexPath: indexPath
                ))
            }
        }

        // Sort newest first
        sessions.sort { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }

        // Cap at 100
        if sessions.count > maxSessions {
            sessions = Array(sessions.prefix(maxSessions))
        }

        return sessions
    }

    // MARK: - SourceReader — load messages

    /// Loads messages from a Gemini session by reading the git commit diff.
    /// Each commit is treated as a single "assistant" message with the commit subject as content.
    func loadMessages(forSessionId id: String) throws -> [SessionMessage] {
        // id format: "gemini:<repoName>:<commitHash>"
        let parts = id.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 3 && parts[0] == "gemini" else { return [] }

        let repoName = String(parts[1])
        let commitHash = String(parts[2])

        let repoDir = historyDir.appendingPathComponent(repoName)
        guard fileManager.fileExists(atPath: repoDir.path) else { return [] }

        // Read the commit subject and date
        let subjectProcess = Process()
        subjectProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        subjectProcess.currentDirectoryURL = repoDir
        subjectProcess.arguments = [
            "log", "-1", "--format=%s%n%aI", commitHash
        ]

        let subjectPipe = Pipe()
        subjectProcess.standardOutput = subjectPipe
        subjectProcess.standardError = FileHandle.nullDevice

        do {
            try subjectProcess.run()
            subjectProcess.waitUntilExit()
        } catch {
            return []
        }

        guard let subjectData = try? subjectPipe.fileHandleForReading.readToEnd(),
              let subjectOutput = String(data: subjectData, encoding: .utf8) else {
            return []
        }

        let subjectLines = subjectOutput.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard subjectLines.count >= 2 else { return [] }

        let subject = subjectLines[0]
        let date = ISO8601DateFormatter().date(from: subjectLines[1])

        // Read the commit diff (body)
        let diffProcess = Process()
        diffProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        diffProcess.currentDirectoryURL = repoDir
        diffProcess.arguments = [
            "show", "--format=", "--no-patch", commitHash
        ]

        // We return one "assistant" message representing the Gemini session commit
        let ts: SessionTimestamp? = date.map { .unixSeconds($0.timeIntervalSince1970) }
        return [
            SessionMessage(
                id: UUID().uuidString,
                role: .assistant,
                content: subject,
                timestamp: ts
            )
        ]
    }

    // MARK: - Helpers

    private func loadProjectRoot(repoDir: URL) -> String? {
        let rootFile = repoDir.appendingPathComponent(".project_root")
        guard let data = try? Data(contentsOf: rootFile),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil : text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct GitLogEntry {
        let commit: String
        let date: Date?
        let subject: String
    }

    /// Uses `git log` via Process to read commit history from a Gemini history dir.
    private func readGitLog(repoDir: URL) -> [GitLogEntry] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = repoDir
        process.arguments = [
            "log", "--format=%H%n%aI%n%s", "--max-count=50"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }

        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let output = String(data: data, encoding: .utf8) else {
            return []
        }

        // Parse blocks separated by newlines: each entry is 3 lines (hash\niso-date\nsubject)
        let lines = output.components(separatedBy: "\n").filter { !$0.isEmpty }
        var entries: [GitLogEntry] = []

        var i = 0
        while i + 2 < lines.count {
            let hash = lines[i]
            let dateStr = lines[i + 1]
            let subject = lines[i + 2]
            let date = ISO8601DateFormatter().date(from: dateStr)
            entries.append(GitLogEntry(commit: hash, date: date, subject: subject))
            i += 3
        }

        return entries
    }
}