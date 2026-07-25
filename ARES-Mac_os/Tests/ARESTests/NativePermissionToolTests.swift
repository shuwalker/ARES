import XCTest
@testable import ARESCore

final class NativePermissionToolTests: XCTestCase {
    @MainActor
    func testCalendarPermissionStatusIsReadOnlyAndDiscoverable() async {
        let tool = CalendarTool()
        XCTAssertTrue(tool.supportedOperations.contains("permission_status"))

        let result = await tool.routeOperation(
            "permission_status",
            parameters: ["operation": "permission_status"],
            context: MCPExecutionContext()
        )

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.content.contains("Calendar permission:"))
        XCTAssertTrue(result.output.content.contains("Reminders permission:"))
    }

    @MainActor
    func testContactsPermissionStatusIsReadOnlyAndDiscoverable() async {
        let tool = ContactsTool()
        XCTAssertTrue(tool.supportedOperations.contains("permission_status"))

        let result = await tool.routeOperation(
            "permission_status",
            parameters: ["operation": "permission_status"],
            context: MCPExecutionContext()
        )

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.output.content.contains("Contacts permission:"))
    }
}
