import Foundation
import ARESCore
import os

private let toolRouterLog = Logger(subsystem: "com.ares", category: "ToolRouter")

/// Routes namespaced tool calls ("provider__tool") to registered ToolProviders.
/// The single integration point between the agent loop and tool execution.
///
/// - Aggregates `listTools()` across providers (namespaced to avoid collisions)
/// - Enforces the approval policy via `ApprovalBroker` before executing
///   any tool flagged `requiresApproval` (or category `.system`)
/// - Tolerates offline providers: a provider whose `listTools()` throws is
///   skipped for that round, never fatal.
public final class ToolRouter: @unchecked Sendable {

    public static let shared = ToolRouter()

    /// Separator between provider identifier and tool name in namespaced tool names.
    public static let namespaceSeparator = "__"

    /// Providers live in the single source of truth: ARESCore's ToolRegistry.
    private var registry: ToolRegistry { ToolRegistry.shared }

    public init() {}

    // MARK: - Registration (delegates to ToolRegistry)

    public func register(_ provider: any ToolProvider) {
        registry.register(provider: provider)
    }

    public func unregister(identifier: String) {
        registry.unregister(identifier: identifier)
    }

    public var registeredProviders: [any ToolProvider] {
        registry.allProviders()
    }

    public var hasProviders: Bool {
        !registry.allProviders().isEmpty
    }

    // MARK: - Discovery

    /// All tools from all reachable providers, with namespaced names.
    /// A provider that throws is logged and skipped — never fatal.
    public func availableTools() async -> [Tool] {
        var result: [Tool] = []
        for provider in registeredProviders {
            do {
                let tools = try await provider.listTools()
                for tool in tools {
                    result.append(Tool(
                        name: provider.identifier + Self.namespaceSeparator + tool.name,
                        description: "[\(provider.displayName)] \(tool.description)",
                        inputSchema: tool.inputSchema,
                        outputSchema: tool.outputSchema,
                        requiresApproval: tool.requiresApproval,
                        category: tool.category
                    ))
                }
            } catch {
                toolRouterLog.warning("listTools failed for \(provider.identifier, privacy: .public): \(error.localizedDescription, privacy: .public) — skipping")
            }
        }
        return result
    }

    // MARK: - Execution

    /// Execute a namespaced tool call, enforcing the approval policy first.
    public func execute(_ call: ToolCall) async -> ToolResult {
        let parts = call.toolName.components(separatedBy: Self.namespaceSeparator)
        guard parts.count >= 2, let provider = registry.getProvider(for: parts[0]) else {
            return ToolResult(
                success: false,
                error: ToolError(code: .notFound, message: "Unknown tool '\(call.toolName)'. Expected provider\(Self.namespaceSeparator)tool.")
            )
        }
        let bareToolName = parts.dropFirst().joined(separator: Self.namespaceSeparator)

        // Resolve the tool definition to read its approval flag.
        var requiresApproval = true // default-deny if we can't resolve the tool
        var toolDescription = ""
        if let tools = try? await provider.listTools(),
           let tool = tools.first(where: { $0.name == bareToolName }) {
            requiresApproval = tool.requiresApproval || tool.category == .system
            toolDescription = tool.description
        }

        if requiresApproval {
            let approved = await ApprovalBroker.shared.requestApproval(
                providerName: provider.displayName,
                toolName: bareToolName,
                toolDescription: toolDescription,
                input: call.input
            )
            guard approved else {
                toolRouterLog.notice("Denied by user: \(call.toolName, privacy: .public)")
                return ToolResult(
                    success: false,
                    error: ToolError(code: .permissionDenied, message: "The user denied permission to run '\(bareToolName)'.")
                )
            }
        }

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let bareCall = ToolCall(id: call.id, toolName: bareToolName, input: call.input)
            let result = try await provider.execute(toolName: bareToolName, input: bareCall.input)
            toolRouterLog.info("Executed \(call.toolName, privacy: .public) success=\(result.success)")
            return result
        } catch {
            let ms = (CFAbsoluteTimeGetCurrent() - start) * 1000
            toolRouterLog.error("Execution failed for \(call.toolName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return ToolResult(
                success: false,
                error: ToolError(code: .executionFailed, message: error.localizedDescription),
                executionTimeMs: ms
            )
        }
    }
}

// MARK: - AnyCodable <-> Any bridging (JSON request bodies)

public enum ToolJSON {
    /// Convert AnyCodable to a Foundation JSON-compatible value.
    public static func any(from value: AnyCodable) -> Any {
        switch value {
        case .string(let s): return s
        case .number(let d): return d
        case .bool(let b): return b
        case .array(let a): return a.map { any(from: $0) }
        case .object(let o): return o.mapValues { any(from: $0) }
        case .null: return NSNull()
        }
    }

    /// Convert a Foundation JSON value to AnyCodable.
    public static func anyCodable(from value: Any) -> AnyCodable {
        switch value {
        case let s as String: return .string(s)
        case let b as Bool: return .bool(b)
        case let n as NSNumber:
            // NSNumber bool detection already handled above for Swift Bool;
            // CFBoolean bridges to Bool in the earlier case on Apple platforms.
            return .number(n.doubleValue)
        case let d as Double: return .number(d)
        case let i as Int: return .number(Double(i))
        case let a as [Any]: return .array(a.map { anyCodable(from: $0) })
        case let o as [String: Any]: return .object(o.mapValues { anyCodable(from: $0) })
        default: return .null
        }
    }

    public static func dictionary(from input: [String: AnyCodable]) -> [String: Any] {
        input.mapValues { any(from: $0) }
    }

    public static func input(from dictionary: [String: Any]) -> [String: AnyCodable] {
        dictionary.mapValues { anyCodable(from: $0) }
    }

    /// JSONSchema -> JSON dictionary (shared by all gateway encoders).
    public static func schemaDictionary(_ schema: JSONSchema) -> [String: Any] {
        var dict: [String: Any] = ["type": schema.type]
        if let description = schema.description { dict["description"] = description }
        if let properties = schema.properties {
            var props: [String: Any] = [:]
            for (key, property) in properties {
                var p: [String: Any] = ["type": property.type]
                if let d = property.description { p["description"] = d }
                if let e = property.enum { p["enum"] = e }
                props[key] = p
            }
            dict["properties"] = props
        }
        if let required = schema.required { dict["required"] = required }
        return dict
    }
}

// MARK: - Per-gateway tool encodings

public enum GatewayToolEncoding {
    /// Anthropic Messages API: [{name, description, input_schema}]
    public static func anthropic(_ tools: [Tool]) -> [[String: Any]] {
        tools.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "input_schema": ToolJSON.schemaDictionary(tool.inputSchema)
            ]
        }
    }

    /// Ollama /api/chat & OpenAI chat completions: [{type:"function", function:{name, description, parameters}}]
    public static func openAIFunction(_ tools: [Tool]) -> [[String: Any]] {
        tools.map { tool in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": ToolJSON.schemaDictionary(tool.inputSchema)
                ] as [String: Any]
            ]
        }
    }
}
