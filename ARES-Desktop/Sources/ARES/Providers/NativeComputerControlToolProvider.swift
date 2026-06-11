import Foundation
import ARESCore

/// Native Computer Control Tool Provider.
/// Proxies OS-level interactions through native Swift instead of raw Python scripts.
/// This ensures macOS attributes security permissions (like Accessibility or System Events)
/// to the ARES app, preventing confusing popup dialogs that attribute control to "python3.11".
public final class NativeComputerControlToolProvider: ToolProvider, @unchecked Sendable {
    public let identifier = "native_computer_control"
    public let displayName = "macOS Native Computer Control"
    public var capabilities: Set<String> { ["executeApplescript"] }

    public init() {
        print("✅ [WIRING] NativeComputerControlToolProvider initialized")
    }

    public func listTools() async throws -> [Tool] {
        return [
            Tool(
                name: "execute_applescript",
                description: "Executes an AppleScript natively on the macOS system. Useful for controlling apps, sending keystrokes, and UI scripting.",
                inputSchema: JSONSchema(
                    type: "object",
                    properties: [
                        "script": JSONSchema.Property(type: "string", description: "The AppleScript code to execute.")
                    ],
                    required: ["script"]
                ),
                outputSchema: JSONSchema(type: "object"),
                category: .system
            )
        ]
    }

    public func execute(toolName: String, input: [String: AnyCodable]) async throws -> ToolResult {
        guard toolName == "execute_applescript" else {
            return ToolResult(
                success: false,
                error: ToolError(code: .notFound, message: "Tool \(toolName) not supported by NativeComputerControlToolProvider.")
            )
        }

        guard case .string(let script) = input["script"] else {
            return ToolResult(
                success: false,
                error: ToolError(code: .validationFailed, message: "Missing required parameter 'script' of type string.")
            )
        }

        let startTime = Date()

        return await withCheckedContinuation { continuation in
            var errorInfo: NSDictionary? = nil
            if let appleScript = NSAppleScript(source: script) {
                let eventDescriptor = appleScript.executeAndReturnError(&errorInfo)
                let duration = Date().timeIntervalSince(startTime) * 1000

                if let errorInfo = errorInfo {
                    let errorMessage = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown AppleScript error"
                    continuation.resume(returning: ToolResult(
                        success: false,
                        error: ToolError(code: .executionFailed, message: "AppleScript failed: \(errorMessage)"),
                        executionTimeMs: duration
                    ))
                } else {
                    let output = eventDescriptor.stringValue ?? "Success"
                    continuation.resume(returning: ToolResult(
                        success: true,
                        data: .string(output),
                        executionTimeMs: duration
                    ))
                }
            } else {
                continuation.resume(returning: ToolResult(
                    success: false,
                    error: ToolError(code: .executionFailed, message: "Failed to compile AppleScript.")
                ))
            }
        }
    }

    public func validateInput(_ input: [String: AnyCodable], forToolNamed name: String) async throws -> Bool {
        if name == "execute_applescript" {
            return input["script"] != nil
        }
        return false
    }
}
