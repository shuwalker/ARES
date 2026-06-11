import XCTest
import ARESCore
@testable import ARES

/// Contract tests for the REAL brick implementations — the ones a normal
/// launch actually wires. Each test runs against a fresh temp directory so
/// nothing touches ~/.ares.
final class FileSystemIdentityTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ares-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private var identityPath: String { tempDir.appendingPathComponent("identity.json").path }

    func testFirstLaunchCreatesIdentityFile() throws {
        _ = try FileSystemIdentity(path: identityPath)
        XCTAssertTrue(FileManager.default.fileExists(atPath: identityPath))
    }

    func testDisplayNameSurvivesRelaunch() async throws {
        let identity = try FileSystemIdentity(path: identityPath)
        let originalID = identity.id
        try await identity.updateDisplayName("ARES Test Unit")

        // Simulate app relaunch: a fresh instance must load the same identity.
        let reloaded = try FileSystemIdentity(path: identityPath)
        XCTAssertEqual(reloaded.id, originalID)
        XCTAssertEqual(reloaded.displayName, "ARES Test Unit")
    }

    func testCorruptIdentityFileRecovers() throws {
        try Data("not json at all".utf8).write(to: URL(fileURLWithPath: identityPath))
        let identity = try FileSystemIdentity(path: identityPath)
        XCTAssertFalse(identity.displayName.isEmpty)
        // Recovery must rewrite a valid file.
        let data = try Data(contentsOf: URL(fileURLWithPath: identityPath))
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
    }
}

final class FileSystemWorkflowTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ares-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testFirstLaunchSeedsMainBoard() async throws {
        let workflow = try FileSystemWorkflow(path: tempDir.path)
        let boards = try await workflow.listBoards()
        XCTAssertEqual(boards.map(\.name), ["main"])
        XCTAssertEqual(boards[0].columns.count, 3)
    }

    func testCardLifecyclePersistsAcrossRelaunch() async throws {
        let workflow = try FileSystemWorkflow(path: tempDir.path)
        let card = try await workflow.createCard(
            in: "main", column: "todo",
            title: "Ship v1", description: "no dummies reachable"
        )

        // Move to done, rename, then relaunch and verify everything stuck.
        _ = try await workflow.moveCard(card.id, toBoard: "main", toColumn: "done")
        _ = try await workflow.updateCard(card.id, title: "Ship v1.0", description: nil, metadata: nil)

        let reloaded = try FileSystemWorkflow(path: tempDir.path)
        let board = try await reloaded.getBoard("main")
        XCTAssertEqual(board.cards.count, 1)
        let persisted = try XCTUnwrap(board.cards.first)
        XCTAssertEqual(persisted.title, "Ship v1.0")
        let doneColumn = try XCTUnwrap(board.columns.first { $0.name == "done" })
        XCTAssertEqual(persisted.columnId, doneColumn.id)
    }

    func testDeleteCardRemovesItFromDisk() async throws {
        let workflow = try FileSystemWorkflow(path: tempDir.path)
        let card = try await workflow.createCard(in: "main", column: "todo", title: "temp", description: nil)
        try await workflow.deleteCard(card.id, from: "main")

        let reloaded = try FileSystemWorkflow(path: tempDir.path)
        let board = try await reloaded.getBoard("main")
        XCTAssertTrue(board.cards.isEmpty)
    }

    func testUnknownBoardAndColumnThrow() async throws {
        let workflow = try FileSystemWorkflow(path: tempDir.path)
        do {
            _ = try await workflow.getBoard("nope")
            XCTFail("Expected boardNotFound")
        } catch {}
        do {
            _ = try await workflow.createCard(in: "main", column: "nope", title: "x", description: nil)
            XCTFail("Expected columnNotFound")
        } catch {}
    }
}

final class SQLiteMemoryStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ares-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private var dbPath: String { tempDir.appendingPathComponent("state.db").path }

    func testStoreAndRetrieveWithoutEmbedder() async throws {
        // embedder: nil exercises the text-matching fallback — the path the
        // app takes when Ollama isn't running. It must still work.
        let store = try SQLiteMemoryStore(path: dbPath, embedder: nil)
        let id = try await store.store(Memory(content: "The owner's favorite color is teal"))
        XCTAssertFalse(id.isEmpty)

        let hits = try await store.retrieve(query: "favorite color", limit: 5)
        XCTAssertTrue(hits.contains { $0.id == id }, "stored memory should be retrievable by text match")
    }

    func testMemorySurvivesRelaunch() async throws {
        let store = try SQLiteMemoryStore(path: dbPath, embedder: nil)
        let id = try await store.store(Memory(content: "persistent fact about robotics"))

        let reopened = try SQLiteMemoryStore(path: dbPath, embedder: nil)
        let hits = try await reopened.retrieve(query: "robotics", limit: 5)
        XCTAssertTrue(hits.contains { $0.id == id }, "memory must survive process restart")
    }

    func testDeleteRemovesMemory() async throws {
        let store = try SQLiteMemoryStore(path: dbPath, embedder: nil)
        let id = try await store.store(Memory(content: "ephemeral note about quokkas"))
        try await store.delete(id)
        let hits = try await store.retrieve(query: "quokkas", limit: 5)
        XCTAssertFalse(hits.contains { $0.id == id })
    }
}

final class ARESConfigurationTests: XCTestCase {
    func testMalformedURLsFallBackToDefaults() {
        let config = ARESConfiguration.shared
        let savedHermes = config.hermesURL
        let savedOllama = config.ollamaURL
        defer {
            config.hermesURL = savedHermes
            config.ollamaURL = savedOllama
        }

        config.hermesURL = "not a url at all"
        config.ollamaURL = ""
        XCTAssertEqual(config.hermesBaseURL.absoluteString, "http://localhost:8642")
        XCTAssertEqual(config.ollamaBaseURL.absoluteString, "http://localhost:11434")
    }

    func testCustomURLsParse() {
        let config = ARESConfiguration.shared
        let saved = config.hermesURL
        defer { config.hermesURL = saved }

        config.hermesURL = "http://100.85.249.11:8642"
        XCTAssertEqual(config.hermesBaseURL.host, "100.85.249.11")
        XCTAssertEqual(config.hermesBaseURL.port, 8642)
    }
}
