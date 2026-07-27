import Foundation
import Logging

/// MCP tool that reads on-screen window/accessibility state so ARES can "see"
/// what the user is doing — strictly per-read, consent-gated, deny-by-default.
///
/// Two independent gates must both pass before any screen data is returned:
///   1. **User consent** for this conversation + operation, via
///      `AuthorizationManager` (one-time-use grant, deny by default).
///   2. **OS permission** (macOS Accessibility), reported honestly — if the
///      permission is not granted, the tool returns an actionable error instead
///      of silently returning nothing.
public final class ScreenReadTool: MCPTool, @unchecked Sendable {
    public let name = "screen_read"
    public let description = """
    Read the current on-screen window state (application names and window \
    titles) so the assistant can understand what the user is looking at.

    **Privacy**: This is a system-category capability. Every call requires \
    explicit per-read user consent AND macOS Accessibility permission. Without \
    both, the call is denied and no screen data is returned.
    """

    /// Operation key used for the consent grant.
    public static let operation = "screen_read.window_snapshot"

    public var parameters: [String: MCPToolParameter] { [:] }

    private let logger = Logger(label: "com.ares.mcp.ScreenReadTool")
    private let service: ScreenAccessibilityService

    public init(service: ScreenAccessibilityService = ScreenAccessibilityService()) {
        self.service = service
    }

    public func initialize() async throws {}

    public func execute(parameters: [String: Any], context: MCPExecutionContext) async -> MCPToolResult {
        // Gate 1 — user consent (deny by default). Requires a conversation to
        // scope the grant to, and a prior one-time-use authorization.
        guard let conversationId = context.conversationId else {
            return deny("No conversation context; cannot verify screen-read consent.")
        }
        guard AuthorizationManager.shared.isAuthorized(
            conversationId: conversationId,
            operation: Self.operation
        ) else {
            return deny(
                "Screen read denied: no user consent. Request approval via "
                + "user_collaboration for operation \"\(Self.operation)\" before reading the screen."
            )
        }

        // Gate 2 — OS permission, reported honestly.
        switch service.accessibilityPermission() {
        case .granted:
            break
        case .denied:
            return deny(
                "Screen read unavailable: macOS Accessibility permission is not granted. "
                + "Grant ARES access in System Settings → Privacy & Security → Accessibility."
            )
        case .unsupported:
            return deny("Screen read is not supported on this platform.")
        }

        let windows = service.windowSnapshot()
        let lines = windows.map { window -> String in
            let title = window.windowTitle.map { ": \($0)" } ?? ""
            return "- \(window.ownerName)\(title)"
        }
        let content = lines.isEmpty
            ? "No on-screen windows were visible."
            : "On-screen windows:\n" + lines.joined(separator: "\n")

        logger.debug("screen_read returned \(windows.count) windows")
        return MCPToolResult(
            toolName: name,
            success: true,
            output: MCPOutput(content: content, mimeType: "text/plain")
        )
    }

    public func validateParameters(_ parameters: [String: Any]) throws -> Bool {
        true
    }

    private func deny(_ message: String) -> MCPToolResult {
        MCPToolResult(
            toolName: name,
            success: false,
            output: MCPOutput(content: "ERROR: \(message)", mimeType: "text/plain")
        )
    }
}
