import XCTest
@testable import ARESCore

final class ToolResultStorageTests: XCTestCase {
    private var directory: URL!
    private var storage: ToolResultStorage!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ares-tool-results-\(UUID().uuidString)", isDirectory: true)
        storage = ToolResultStorage(storageDirectory: directory.path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
        storage = nil
        directory = nil
    }

    func testResultsAreScopedByConversation() throws {
        try storage.persistResult(content: "alpha", toolCallId: "call_1", conversationId: "conversation-a")
        try storage.persistResult(content: "beta", toolCallId: "call_1", conversationId: "conversation-b")

        XCTAssertEqual(try storage.retrieve(toolCallId: "call_1", conversationId: "conversation-a"), "alpha")
        XCTAssertEqual(try storage.retrieve(toolCallId: "call_1", conversationId: "conversation-b"), "beta")
        XCTAssertThrowsError(try storage.retrieve(toolCallId: "call_1", conversationId: "conversation-c"))
    }

    func testInvalidOffsetsThrowInsteadOfTrappingOrClamping() throws {
        try storage.persistResult(content: "hello", toolCallId: "call_2", conversationId: "conversation-a")

        XCTAssertThrowsError(try storage.retrieveChunk(toolCallId: "call_2", offset: -1, conversationId: "conversation-a"))
        XCTAssertThrowsError(try storage.retrieveChunk(toolCallId: "call_2", offset: 6, conversationId: "conversation-a"))
        XCTAssertEqual(
            try storage.retrieveChunk(toolCallId: "call_2", offset: 5, conversationId: "conversation-a").content,
            ""
        )
    }

    func testChunkOffsetsCountExtendedGraphemeClusters() throws {
        try storage.persistResult(content: "A👩🏽‍💻B", toolCallId: "call_3", conversationId: "conversation-a")

        let chunk = try storage.retrieveChunk(
            toolCallId: "call_3",
            offset: 1,
            length: 1,
            conversationId: "conversation-a"
        )
        XCTAssertEqual(chunk.content, "👩🏽‍💻")
        XCTAssertEqual(chunk.offset, 1)
        XCTAssertEqual(chunk.length, 1)
        XCTAssertTrue(chunk.hasMore)
    }

    func testIdentifiersCannotEscapeStorageDirectory() throws {
        XCTAssertThrowsError(
            try storage.persistResult(
                content: "secret",
                toolCallId: "../escape",
                conversationId: "conversation-a"
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.deletingLastPathComponent().appendingPathComponent("escape").path))
    }
}
