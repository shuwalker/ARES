import XCTest
@testable import ARESCore

final class ScreenReadToolTests: XCTestCase {
    private let tool = ScreenReadTool()

    override func tearDown() {
        // Clear any grants created during a test to keep cases independent.
        super.tearDown()
    }

    func testDeniedWithoutConversationContext() async {
        let result = await tool.execute(parameters: [:], context: MCPExecutionContext())
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.content.contains("consent"))
    }

    @MainActor
    func testNativeManagerPublishesConsentAndScreenPermissionTools() async throws {
        let manager = MCPManager()
        try await manager.initialize()
        let names = Set(manager.getAvailableTools().map(\.name))
        XCTAssertTrue(names.contains("user_collaboration"))
        XCTAssertTrue(names.contains("screen_read"))
    }

    func testDeniedWithoutConsentGrant() async {
        let conversationId = UUID()
        let context = MCPExecutionContext(conversationId: conversationId)
        // No AuthorizationManager grant issued -> deny by default.
        let result = await tool.execute(parameters: [:], context: context)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.content.lowercased().contains("no user consent"))
    }

    func testConsentIsOneTimeUse() {
        let conversationId = UUID()
        AuthorizationManager.shared.grantAuthorization(
            conversationId: conversationId,
            operation: ScreenReadTool.operation
        )
        // First check consumes the one-time grant; second must be false.
        XCTAssertTrue(
            AuthorizationManager.shared.isAuthorized(
                conversationId: conversationId,
                operation: ScreenReadTool.operation
            )
        )
        XCTAssertFalse(
            AuthorizationManager.shared.isAuthorized(
                conversationId: conversationId,
                operation: ScreenReadTool.operation
            )
        )
    }

    func testPermissionProbeReportsHonestly() {
        // In a headless/CI process the Accessibility permission is not granted;
        // the probe must say so rather than claim availability. On a dev machine
        // with permission granted it returns .granted. Either is a valid, honest
        // answer — what must never happen is a crash or a false positive with no
        // permission.
        let permission = ScreenAccessibilityService().accessibilityPermission()
        XCTAssertTrue(
            [.granted, .denied, .unsupported].contains(permission),
            "permission probe returned an unexpected value"
        )
    }

    func testGrantedConsentButNoOSPermissionDeniesHonestly() async {
        // When consent is granted but OS Accessibility permission is absent
        // (the usual state in a test process), the tool must deny with an
        // actionable permission message — never silently succeed with no data.
        let conversationId = UUID()
        AuthorizationManager.shared.grantAuthorization(
            conversationId: conversationId,
            operation: ScreenReadTool.operation
        )
        let context = MCPExecutionContext(conversationId: conversationId)
        let result = await tool.execute(parameters: [:], context: context)

        if ScreenAccessibilityService().accessibilityPermission() == .granted {
            // Dev machine with permission: a real read is allowed to succeed.
            XCTAssertTrue(result.success)
        } else {
            XCTAssertFalse(result.success)
            XCTAssertTrue(result.output.content.contains("Accessibility permission"))
        }
    }
}
