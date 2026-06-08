import Foundation

/// Tool provider: exposes callable functions with input validation and execution.
/// Conforming types: FileSystemToolProvider, WebToolProvider, CodeExecutionToolProvider
///
/// Design: Based on MCP (Model Context Protocol). Each tool has:
/// - Name and description (for LLM context)
/// - Input schema (for validation)
/// - Execute closure (for invocation)
/// - Capability flags (for gating)
public protocol ToolProvider: AnyObject, Sendable {
    /// Unique identifier for this tool provider.
    /// Examples: "file_system", "web_search", "code_execution"
    var identifier: String { get }

    /// Human-readable name.
    var displayName: String { get }

    /// What this provider can do.
    /// Examples: ["readFile", "writeFile", "listDirectory"]
    var capabilities: Set<String> { get }

    /// List all available tools.
    func listTools() async throws -> [Tool]

    /// Execute a tool by name with the given input.
    /// Returns structured result or error.
    func execute(toolName: String, input: [String: AnyCodable]) async throws -> ToolResult

    /// Validate input against a tool's schema before execution.
    func validateInput(_ input: [String: AnyCodable], forToolNamed name: String) async throws -> Bool
}

/// A single tool: name, description, input schema, output schema.
public struct Tool: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let inputSchema: JSONSchema
    public let outputSchema: JSONSchema
    public let requiresApproval: Bool
    public let category: ToolCategory

    public enum ToolCategory: String, Codable, Sendable {
        case fileSystem = "file_system"
        case network = "network"
        case computation = "computation"
        case media = "media"
        case system = "system"
        case custom
    }

    public init(
        name: String,
        description: String,
        inputSchema: JSONSchema,
        outputSchema: JSONSchema,
        requiresApproval: Bool = false,
        category: ToolCategory = .custom
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.requiresApproval = requiresApproval
        self.category = category
    }
}

/// Result of tool execution.
public struct ToolResult: Codable, Sendable, Equatable {
    public let success: Bool
    public let data: AnyCodable?
    public let error: ToolError?
    public let executionTimeMs: Double
    public let metadata: [String: AnyCodable]

    public init(
        success: Bool,
        data: AnyCodable? = nil,
        error: ToolError? = nil,
        executionTimeMs: Double = 0,
        metadata: [String: AnyCodable] = [:]
    ) {
        self.success = success
        self.data = data
        self.error = error
        self.executionTimeMs = executionTimeMs
        self.metadata = metadata
    }
}

/// Tool execution error with code and message.
public struct ToolError: Codable, Sendable, Equatable {
    public let code: ErrorCode
    public let message: String
    public let details: [String: AnyCodable]?

    public enum ErrorCode: String, Codable, Sendable {
        case validationFailed = "validation_failed"
        case executionFailed = "execution_failed"
        case permissionDenied = "permission_denied"
        case notFound = "not_found"
        case timeout = "timeout"
        case unknown
    }

    public init(
        code: ErrorCode,
        message: String,
        details: [String: AnyCodable]? = nil
    ) {
        self.code = code
        self.message = message
        self.details = details
    }
}

/// JSON schema for tool input/output validation.
public struct JSONSchema: Codable, Sendable, Equatable {
    public let type: String  // "object", "string", "number", "array", "boolean"
    public let properties: [String: Property]?
    public let required: [String]?
    public let description: String?

    public struct Property: Codable, Sendable, Equatable {
        public let type: String
        public let description: String?
        public let `enum`: [String]?

        public init(
            type: String,
            description: String? = nil,
            enum: [String]? = nil
        ) {
            self.type = type
            self.description = description
            self.enum = `enum`
        }
    }

    public init(
        type: String,
        properties: [String: Property]? = nil,
        required: [String]? = nil,
        description: String? = nil
    ) {
        self.type = type
        self.properties = properties
        self.required = required
        self.description = description
    }
}
