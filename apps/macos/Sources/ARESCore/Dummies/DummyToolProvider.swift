import Foundation

/// No-op ToolProvider for testing.
public final class DummyToolProvider: ToolProvider, @unchecked Sendable {
    public let identifier = "dummy_tools"
    public let displayName = "Dummy Tool Provider"
    public var capabilities: Set<String> { ["echo"] }

    public init() {}

    public func listTools() async throws -> [Tool] {
        [Tool(
            name: "echo",
            description: "Echo input back",
            inputSchema: JSONSchema(type: "object"),
            outputSchema: JSONSchema(type: "object")
        )]
    }

    public func execute(toolName: String, input: [String: AnyCodable]) async throws -> ToolResult {
        print("🤖 [DUMMY] Tool: \(toolName) input: \(input)")
        return ToolResult(success: true, data: AnyCodable.object(input))
    }

    public func validateInput(_ input: [String: AnyCodable], forToolNamed name: String) async throws -> Bool {
        true
    }
}
