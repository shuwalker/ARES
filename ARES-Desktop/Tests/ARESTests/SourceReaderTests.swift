import XCTest
@testable import ARES

final class SourceReaderTests: XCTestCase {

    // MARK: - Helpers

    /// A directory that definitely does not exist, for testing graceful failure.
    private var nonexistentDir: URL {
        URL(fileURLWithPath: "/tmp/ares_test_nonexistent_\(UUID().uuidString)")
    }

    // MARK: - Claude Code reader

    func testClaudeReaderMissingDir() throws {
        let reader = ClaudeSessionReader(projectsDir: nonexistentDir)
        XCTAssertFalse(reader.isAvailable, "Claude reader should report unavailable for missing dir")
        let sessions = try reader.listSessions()
        XCTAssertTrue(sessions.isEmpty, "Should return empty array for missing dir")
    }

    func testClaudeReaderRealData() throws {
        let reader = ClaudeSessionReader()
        if !reader.isAvailable {
            print("[INFO] Claude Code data not found on this machine — skipping real-data test")
            return
        }
        let sessions = try reader.listSessions()
        print("[CLAUDE] session count: \(sessions.count)")
        XCTAssertLessThanOrEqual(sessions.count, 100, "Should cap at 100")
        // Verify sorted newest first
        let dates = sessions.compactMap { $0.updatedAt }
        for i in 0..<(dates.count - 1) {
            XCTAssertGreaterThanOrEqual(dates[i], dates[i + 1], "Sessions should be sorted newest first")
        }
        // All sessions should have source claude_code
        for s in sessions {
            XCTAssertEqual(s.source, "claude_code")
            XCTAssertTrue(s.id.hasPrefix("claude_code:"), "ID should be source-prefixed")
        }
    }

    // MARK: - Gemini reader

    func testGeminiReaderMissingDir() throws {
        let reader = GeminiSessionReader(historyDir: nonexistentDir)
        XCTAssertFalse(reader.isAvailable)
        let sessions = try reader.listSessions()
        XCTAssertTrue(sessions.isEmpty)
    }

    func testGeminiReaderRealData() throws {
        let reader = GeminiSessionReader()
        if !reader.isAvailable {
            print("[INFO] Gemini CLI data not found on this machine — skipping real-data test")
            return
        }
        let sessions = try reader.listSessions()
        print("[GEMINI] session count: \(sessions.count)")
        XCTAssertLessThanOrEqual(sessions.count, 100)
        let dates = sessions.compactMap { $0.updatedAt }
        for i in 0..<(dates.count - 1) {
            XCTAssertGreaterThanOrEqual(dates[i], dates[i + 1])
        }
        for s in sessions {
            XCTAssertEqual(s.source, "gemini")
            XCTAssertTrue(s.id.hasPrefix("gemini:"))
        }
    }

    // MARK: - Odysseus reader

    func testOdysseusReaderMissingDB() throws {
        let reader = OdysseusSessionReader(dbPath: nonexistentDir.appendingPathComponent("fake.db"))
        XCTAssertFalse(reader.isAvailable)
        let sessions = try reader.listSessions()
        XCTAssertTrue(sessions.isEmpty)
    }

    func testOdysseusReaderRealData() throws {
        let reader = OdysseusSessionReader()
        if !reader.isAvailable {
            print("[INFO] Odysseus DB not found on this machine — skipping real-data test")
            return
        }
        let sessions = try reader.listSessions()
        print("[ODYSSEUS] session count: \(sessions.count)")
        XCTAssertLessThanOrEqual(sessions.count, 100)
        for s in sessions {
            XCTAssertEqual(s.source, "odysseus")
            XCTAssertTrue(s.id.hasPrefix("odysseus:"))
        }
    }

    // MARK: - Hermes reader

    func testHermesReaderMissingDir() throws {
        let reader = HermesSessionReader(sessionsDir: nonexistentDir)
        XCTAssertFalse(reader.isAvailable)
        let sessions = try reader.listSessions()
        XCTAssertTrue(sessions.isEmpty)
    }

    func testHermesReaderRealData() throws {
        let reader = HermesSessionReader()
        if !reader.isAvailable {
            print("[INFO] Hermes sessions dir not found — skipping real-data test")
            return
        }
        let sessions = try reader.listSessions()
        print("[HERMES] session count: \(sessions.count)")
        XCTAssertLessThanOrEqual(sessions.count, 100)
        // Verify sorted newest first
        let dates = sessions.compactMap { $0.updatedAt }
        for i in 0..<(dates.count - 1) {
            XCTAssertGreaterThanOrEqual(dates[i], dates[i + 1])
        }
        for s in sessions {
            XCTAssertEqual(s.source, "hermes")
            XCTAssertTrue(s.id.hasPrefix("hermes:"))
            // Hermes reader is metadata only — should NOT read content
            XCTAssertNil(s.title, "HermesSessionReader should not populate title (metadata only)")
        }
    }

    // MARK: - UnifiedSession baseline

    func testUnifiedSessionCoding() throws {
        let session = UnifiedSession(
            id: "claude_code:abc123",
            source: "claude_code",
            title: "Hello world",
            startedAt: Date(timeIntervalSince1970: 1000),
            updatedAt: Date(timeIntervalSince1970: 2000),
            messageCount: 42,
            workspace: "/Users/me/project",
            indexPath: "projects/foo/abc123.jsonl"
        )
        let encoder = JSONEncoder()
        let data = try encoder.encode(session)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(UnifiedSession.self, from: data)
        XCTAssertEqual(decoded.id, session.id)
        XCTAssertEqual(decoded.source, session.source)
        XCTAssertEqual(decoded.title, session.title)
        XCTAssertEqual(decoded.messageCount, session.messageCount)
        XCTAssertEqual(decoded.indexPath, session.indexPath)
    }
}