import XCTest
@testable import ARESCore

private final class FakeBackend: AgenticFrameworkBackend, @unchecked Sendable {
    let identifier: String
    let kind: ExecutionBackendKind
    let displayName: String
    let capabilities: Set<ExecutionCapability>
    var health: ExecutionBackendHealth
    private(set) var executeCount = 0
    let responseText: String

    init(
        kind: ExecutionBackendKind,
        capabilities: Set<ExecutionCapability>,
        health: ExecutionBackendHealth = ExecutionBackendHealth(state: .healthy),
        responseText: String = "ok"
    ) {
        self.identifier = "fake-\(kind.rawValue)"
        self.kind = kind
        self.displayName = "Fake \(kind.rawValue)"
        self.capabilities = capabilities
        self.health = health
        self.responseText = responseText
    }

    func healthCheck() async -> ExecutionBackendHealth { health }

    func execute(_ request: ExecutionRequest) async throws -> ExecutionResult {
        executeCount += 1
        return ExecutionResult(requestId: request.id, backend: kind, text: responseText)
    }
}

final class ExecutionBackendDispatcherTests: XCTestCase {
    private func request(_ caps: Set<ExecutionCapability>) -> ExecutionRequest {
        ExecutionRequest(
            userIntent: "do a thing",
            context: ConversationContext(conversationId: UUID(), workingDirectory: "/tmp"),
            requiredCapabilities: caps
        )
    }

    func testDispatchExecutesSelectedBackend() async throws {
        let cliWorker = FakeBackend(kind: .cliWorker, capabilities: [.agentTurn, .toolUse], responseText: "from-cli")
        let dispatcher = ExecutionBackendDispatcher(backends: [cliWorker])

        let result = try await dispatcher.dispatch(request([.agentTurn]))

        XCTAssertEqual(result.text, "from-cli")
        XCTAssertEqual(result.backend, .cliWorker)
        XCTAssertEqual(cliWorker.executeCount, 1)
        // Routing provenance is preserved on the result.
        XCTAssertEqual(result.metadata["route_mode"], .string("single:cli_worker"))
    }

    func testUnroutableWhenNoBackendCoversCapability() async throws {
        let cliWorker = FakeBackend(kind: .cliWorker, capabilities: [.agentTurn])
        let dispatcher = ExecutionBackendDispatcher(backends: [cliWorker])

        do {
            _ = try await dispatcher.dispatch(request([.vision]))
            XCTFail("expected unroutable")
        } catch let ExecutionDispatchError.unroutable(missing, _) {
            XCTAssertEqual(missing, [.vision])
            XCTAssertEqual(cliWorker.executeCount, 0)
        }
    }

    func testUnhealthyBackendIsNotDispatched() async throws {
        let down = FakeBackend(
            kind: .cliWorker,
            capabilities: [.agentTurn],
            health: ExecutionBackendHealth(state: .unavailable)
        )
        let dispatcher = ExecutionBackendDispatcher(backends: [down])

        do {
            _ = try await dispatcher.dispatch(request([.agentTurn]))
            XCTFail("expected unroutable due to unhealthy backend")
        } catch ExecutionDispatchError.unroutable {
            XCTAssertEqual(down.executeCount, 0)
        }
    }

    func testPrefersHealthyBackendForCapability() async throws {
        let cliWorker = FakeBackend(kind: .cliWorker, capabilities: [.agentTurn], responseText: "cli")
        let jros = FakeBackend(kind: .jros, capabilities: [.agentTurn], responseText: "jros")
        // Registration order is product policy: the first registered wins the tie.
        let dispatcher = ExecutionBackendDispatcher(backends: [cliWorker, jros])

        let result = try await dispatcher.dispatch(request([.agentTurn]))
        XCTAssertEqual(result.text, "cli")
        XCTAssertEqual(cliWorker.executeCount, 1)
        XCTAssertEqual(jros.executeCount, 0)
    }
}
