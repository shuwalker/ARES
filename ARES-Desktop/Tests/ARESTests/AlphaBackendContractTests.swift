import ARESCore
import XCTest

final class AlphaBackendContractTests: XCTestCase {
    func testEventBusPublishesAndRecordsHistory() async throws {
        let bus = DummyEventBus()
        let event = MemoryEvent(action: "store", memoryId: "mem-1")
        let stream = bus.subscribe(MemoryEvent.self)
        var iterator = stream.makeAsyncIterator()

        try await bus.publish(event)

        let received = await iterator.next()
        XCTAssertEqual(received, event)

        let history = try await bus.history(MemoryEvent.self, limit: 10)
        XCTAssertEqual(history, [event])
    }

    func testMemoryStoreRoundTripsAndUpdatesContent() async throws {
        let store = DummyMemoryStore()
        let memory = Memory(id: "mem-1", content: "Matthew likes local-first tools")

        let id = try await store.store(memory)
        XCTAssertEqual(id, "mem-1")

        var results = try await store.retrieve(query: "LOCAL-FIRST", limit: 5)
        XCTAssertEqual(results.map(\.id), ["mem-1"])

        try await store.update("mem-1", with: ["content": .string("Matthew likes production alpha builds")])
        results = try await store.retrieve(query: "alpha", limit: 5)
        XCTAssertEqual(results.first?.content, "Matthew likes production alpha builds")

        try await store.delete("mem-1")
        results = try await store.retrieve(query: "Matthew", limit: 5)
        XCTAssertTrue(results.isEmpty)
    }

    func testWorkflowPersistsCardChanges() async throws {
        let workflow = DummyWorkflow()

        let card = try await workflow.createCard(
            in: "inbox",
            column: "col-0",
            title: "Prepare alpha",
            description: "Make backend flows testable"
        )
        var board = try await workflow.getBoard("inbox")
        XCTAssertTrue(board.cards.contains { $0.id == card.id })

        board = try await workflow.moveCard(card.id, toBoard: "inbox", toColumn: "col-1")
        XCTAssertEqual(board.cards.first(where: { $0.id == card.id })?.columnId, "col-1")

        let updated = try await workflow.updateCard(
            card.id,
            title: "Prepare production alpha",
            description: nil,
            metadata: ["status": .string("ready")]
        )
        XCTAssertEqual(updated.title, "Prepare production alpha")

        try await workflow.deleteCard(card.id, from: "inbox")
        board = try await workflow.getBoard("inbox")
        XCTAssertFalse(board.cards.contains { $0.id == card.id })
    }

    func testSchedulerPersistsLifecycleAndHistory() async throws {
        let scheduler = DummyScheduler()
        let job = try await scheduler.schedule(
            name: "Reflect",
            expression: "every 5m",
            command: "reflect",
            metadata: ["source": .string("alpha-test")]
        )

        let fetched = try await scheduler.getJob(job.id)
        XCTAssertEqual(fetched.name, "Reflect")

        let updated = try await scheduler.updateJob(job.id, name: "Reflect on memories", expression: nil, metadata: nil)
        XCTAssertEqual(updated.command, "reflect")
        XCTAssertEqual(updated.name, "Reflect on memories")

        try await scheduler.pauseJob(job.id)
        let paused = try await scheduler.getJob(job.id)
        XCTAssertFalse(paused.isEnabled)

        try await scheduler.resumeJob(job.id)
        let resumed = try await scheduler.getJob(job.id)
        XCTAssertTrue(resumed.isEnabled)

        let execution = try await scheduler.triggerNow(job.id)
        XCTAssertEqual(execution.success, true)
        let history = try await scheduler.history(job.id, limit: 1)
        XCTAssertEqual(history, [execution])
    }
}
