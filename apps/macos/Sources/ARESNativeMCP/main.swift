import ARESCore
import Foundation

@main
struct ARESNativeMCPMain {
    static func main() async {
        let manager = MCPManager()
        do {
            try await manager.initialize()
        } catch {
            writeStderr("ARES native MCP initialization failed: \(error.localizedDescription)")
            Foundation.exit(EXIT_FAILURE)
        }

        if CommandLine.arguments.dropFirst().first == "--list-tools" {
            writeJSON(["tools": toolRecords(manager.getAvailableTools())])
            return
        }

        while let line = readLine() {
            guard let data = line.data(using: .utf8),
                  let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                writeJSON(errorResponse(id: NSNull(), code: -32700, message: "Parse error"))
                continue
            }
            if let response = await handle(request, manager: manager) {
                writeJSON(response)
            }
        }
    }

    @MainActor
    private static func handle(
        _ request: [String: Any],
        manager: MCPManager
    ) async -> [String: Any]? {
        let id = request["id"] ?? NSNull()
        let method = request["method"] as? String ?? ""
        switch method {
        case "initialize":
            return response(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [:]],
                "serverInfo": ["name": "ares-native-mcp", "version": "1.0.0"],
            ])
        case "notifications/initialized", "notifications/cancelled":
            return nil
        case "ping":
            return response(id: id, result: [:])
        case "tools/list":
            return response(id: id, result: ["tools": toolRecords(manager.getAvailableTools())])
        case "tools/call":
            guard let params = request["params"] as? [String: Any],
                  let name = params["name"] as? String
            else {
                return errorResponse(id: id, code: -32602, message: "Tool name is required")
            }
            var arguments = params["arguments"] as? [String: Any] ?? [:]
            let contextData = arguments.removeValue(forKey: "_ares_context") as? [String: Any]
            let conversationID = UUID(uuidString: contextData?["conversation_id"] as? String ?? "")
            let sessionID = UUID(uuidString: contextData?["session_id"] as? String ?? "") ?? UUID()
            let workspace = (contextData?["working_directory"] as? String)
                ?? ProcessInfo.processInfo.environment["ARES_MCP_WORKSPACE"]
                ?? FileManager.default.currentDirectoryPath
            let context = MCPExecutionContext(
                conversationId: conversationID,
                sessionId: sessionID,
                isExternalAPICall: true,
                isUserInitiated: false,
                userRequestText: contextData?["user_request"] as? String,
                workingDirectory: workspace
            )
            do {
                let result = try await manager.executeTool(
                    name: name,
                    parameters: arguments,
                    context: context
                )
                return response(id: id, result: [
                    "content": [["type": "text", "text": result.output.content]],
                    "isError": !result.success,
                ])
            } catch {
                return response(id: id, result: [
                    "content": [["type": "text", "text": "ERROR: \(error.localizedDescription)"]],
                    "isError": true,
                ])
            }
        default:
            return errorResponse(id: id, code: -32601, message: "Method not found")
        }
    }

    private static func toolRecords(_ tools: [any MCPTool]) -> [[String: Any]] {
        tools.map { tool in
            var properties: [String: Any] = [:]
            var required: [String] = []
            for (name, parameter) in tool.parameters {
                properties[name] = parameterSchema(parameter)
                if parameter.required { required.append(name) }
            }
            var inputSchema: [String: Any] = [
                "type": "object",
                "properties": properties,
                "additionalProperties": true,
            ]
            if !required.isEmpty { inputSchema["required"] = required.sorted() }
            return [
                "name": tool.name,
                "description": tool.description,
                "inputSchema": inputSchema,
            ]
        }
    }

    private static func parameterSchema(_ parameter: MCPToolParameter) -> [String: Any] {
        var schema: [String: Any] = [
            "type": parameter.type.description,
            "description": parameter.description,
        ]
        if let values = parameter.enumValues { schema["enum"] = values }
        if parameter.type.description == "array", let itemType = parameter.arrayElementType {
            schema["items"] = ["type": itemType.description]
        }
        return schema
    }

    private static func response(id: Any, result: Any) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "result": result]
    }

    private static func errorResponse(id: Any, code: Int, message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
    }

    private static func writeJSON(_ value: Any) {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value),
              let line = String(data: data, encoding: .utf8)
        else { return }
        print(line)
        fflush(stdout)
    }

    private static func writeStderr(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
