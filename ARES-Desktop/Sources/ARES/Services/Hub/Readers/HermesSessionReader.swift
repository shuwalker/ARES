import Foundation

/// Reads session metadata from Hermes Agent's session files under ~/.hermes/sessions/.
/// This reader is METADATA ONLY — it does not read session content.
/// It lists files, their modification times, and sizes so Block 4 can later
/// read the actual content with a different access pattern.
final class HermesSessionReader: SourceReader {

    // MARK: - SourceReader conformance

    let sourceName = "hermes"

    var isAvailable: Bool {
        FileManager.default.fileExists(atPath: sessionsDir.path)
    }

    // MARK: - Internals

    private let sessionsDir: URL
    private let fileManager = FileManager.default
    private let maxSessions = 100

    /// Initialise with an explicit directory (defaults to ~/.hermes/sessions/).
    init(sessionsDir: URL? = nil) {
        self.sessionsDir = sessionsDir
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".hermes/sessions")
    }

    func listSessions() throws -> [UnifiedSession] {
        guard isAvailable else { return [] }

        let files = try fileManager.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "json" }

        // Build metadata entries
        var sessions: [(session: UnifiedSession, modDate: Date)] = []

        for fileURL in files {
            let attrs = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey])
            let modDate = attrs?.contentModificationDate ?? .distantPast

            // Derive session ID from filename (strip .json extension)
            // Hermes session files look like request_dump_20260529_105826_bbeb2c_...json
            // or may be UUIDs.  Use the stem as a stable identifier.
            let stem = fileURL.deletingPathExtension().lastPathComponent

            // indexPath is relative to sessionsDir
            let indexPath = fileURL.lastPathComponent

            sessions.append((
                session: UnifiedSession(
                    id: "hermes:\(stem)",
                    source: sourceName,
                    title: nil,  // Metadata only — Block 4 reads content
                    startedAt: nil,
                    updatedAt: modDate,
                    messageCount: nil,
                    workspace: nil,
                    indexPath: indexPath
                ),
                modDate: modDate
            ))
        }

        // Sort newest first
        sessions.sort { $0.modDate > $1.modDate }

        // Cap at 100
        let capped = Array(sessions.prefix(maxSessions))

        return capped.map { $0.session }
    }
}