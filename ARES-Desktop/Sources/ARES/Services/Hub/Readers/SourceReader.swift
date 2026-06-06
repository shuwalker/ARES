import Foundation

// MARK: - Protocol

/// A reader that discovers sessions from a specific AI tool (Claude Code,
/// Gemini CLI, Odysseus, or Hermes Agent).  Readers are read-only — ARES
/// never writes to another tool's data store.
protocol SourceReader {
    /// Machine-readable identifier: "claude_code", "gemini", "odysseus", "hermes"
    var sourceName: String { get }

    /// Whether the tool's data directory exists on this machine.
    var isAvailable: Bool { get }

    /// List sessions from this source, sorted newest-first, capped at 100.
    func listSessions() throws -> [UnifiedSession]

    /// Load the messages for a specific session by its source-prefixed ID.
    /// Returns an empty array if the session cannot be read (e.g. Hermes is metadata-only).
    func loadMessages(forSessionId id: String) throws -> [SessionMessage]
}

// MARK: - Default implementation (returns empty)

extension SourceReader {
    func loadMessages(forSessionId id: String) throws -> [SessionMessage] {
        return []
    }
}

// MARK: - Unified model

struct UnifiedSession: Identifiable, Codable, Equatable {
    /// Source-prefixed identifier, e.g. "claude_code:abc123"
    let id: String
    /// Which reader produced this entry ("claude_code", "gemini", "odysseus", "hermes")
    let source: String
    /// First user message truncated to 64 characters, or nil
    let title: String?
    /// When the session started, if known
    let startedAt: Date?
    /// When the session was last updated, if known
    let updatedAt: Date?
    /// Number of messages in the session, if known
    let messageCount: Int?
    /// Working directory / repo path, if known
    let workspace: String?
    /// Relative path into the source data, for Block 4 to read full content
    let indexPath: String

    private enum CodingKeys: String, CodingKey {
        case id, source, title, startedAt, updatedAt, messageCount, workspace, indexPath
    }

    init(
        id: String,
        source: String,
        title: String? = nil,
        startedAt: Date? = nil,
        updatedAt: Date? = nil,
        messageCount: Int? = nil,
        workspace: String? = nil,
        indexPath: String
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.messageCount = messageCount
        self.workspace = workspace
        self.indexPath = indexPath
    }
}

// MARK: - SourceReader uses SessionMessage from SessionModels.swift