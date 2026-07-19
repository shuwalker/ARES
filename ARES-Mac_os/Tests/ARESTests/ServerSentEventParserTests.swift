import XCTest
@testable import ARESCore

final class ServerSentEventParserTests: XCTestCase {
    func testParsesMultilineDataAndIgnoresComments() {
        var parser = ServerSentEventParser()
        XCTAssertNil(parser.consume(line: ": heartbeat"))
        XCTAssertNil(parser.consume(line: "id: run-1:4"))
        XCTAssertNil(parser.consume(line: "event: token"))
        XCTAssertNil(parser.consume(line: "data: {\"text\":"))
        XCTAssertNil(parser.consume(line: "data: \"hello\"}"))

        XCTAssertEqual(
            parser.consume(line: ""),
            ServerSentEvent(
                name: "token",
                data: "{\"text\":\n\"hello\"}",
                id: "run-1:4"
            )
        )
    }

    func testUnknownFieldsAndEmptyEventsDoNotDispatch() {
        var parser = ServerSentEventParser()
        XCTAssertNil(parser.consume(line: "retry: 1000"))
        XCTAssertNil(parser.consume(line: "unknown: value"))
        XCTAssertNil(parser.consume(line: ""))
        XCTAssertNil(parser.finish())
    }

    func testFinishDispatchesFinalUnterminatedEvent() {
        var parser = ServerSentEventParser()
        XCTAssertNil(parser.consume(line: "event: stream_end"))
        XCTAssertNil(parser.consume(line: "data: {\"status\":\"completed\"}"))
        XCTAssertEqual(
            parser.finish(),
            ServerSentEvent(
                name: "stream_end",
                data: "{\"status\":\"completed\"}",
                id: nil
            )
        )
    }
}
