import Foundation
import ARESCore

/// N8N Native Tool Provider.
/// Connects ARES directly to a local or remote n8n instance for workflow automation.
public final class N8NToolProvider: ToolProvider, @unchecked Sendable {
    public let identifier = "n8n_automation"
    public let displayName = "n8n Workflow Automation"
    public var capabilities: Set<String> { ["triggerWorkflow"] }

    private let baseURL: URL

    /// Initializes the provider with the base URL of your n8n instance.
    /// Defaults to the value stored in ARESConfiguration.
    public init(baseURL: String = ARESConfiguration.shared.n8nWebhookBaseURL) {
        self.baseURL = URL(string: baseURL) ?? URL(string: "http://localhost:5678")!
        print("✅ [WIRING] N8NToolProvider initialized targeting \(self.baseURL)")
    }

    public func listTools() async throws -> [Tool] {
        return [
            Tool(
                name: "trigger_n8n_workflow",
                description: "Triggers an n8n workflow by sending a payload to a specific webhook ID. Use this for YouTube uploads, social media, and Google Drive automations.",
                inputSchema: JSONSchema(
                    type: "object",
                    properties: [
                        "webhook_id": JSONSchema.Property(type: "string", description: "The UUID or path of the n8n webhook (e.g. 'ares-youtube-upload')"),
                        "payload": JSONSchema.Property(type: "object", description: "The JSON data to send to the workflow")
                    ],
                    required: ["webhook_id", "payload"]
                ),
                outputSchema: JSONSchema(type: "object"),
                category: .network
            )
        ]
    }

    public func execute(toolName: String, input: [String: AnyCodable]) async throws -> ToolResult {
        guard toolName == "trigger_n8n_workflow" else {
            return ToolResult(
                success: false,
                error: ToolError(code: .notFound, message: "Tool \(toolName) not supported by N8NToolProvider.")
            )
        }

        guard case .string(let webhookId) = input["webhook_id"],
              let payloadAny = input["payload"] else {
            return ToolResult(
                success: false,
                error: ToolError(code: .validationFailed, message: "Missing required parameters 'webhook_id' or 'payload'.")
            )
        }

        let webhookURL = baseURL.appendingPathComponent("webhook/\(webhookId)")
        
        var request = URLRequest(url: webhookURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            // Re-serialize the payload
            let payloadData = try JSONEncoder().encode(payloadAny)
            request.httpBody = payloadData
            
            let startTime = Date()
            let (data, response) = try await URLSession.shared.data(for: request)
            let duration = Date().timeIntervalSince(startTime) * 1000

            if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                // Try to parse the n8n JSON response
                if let anyCodable = try? JSONDecoder().decode(AnyCodable.self, from: data) {
                    return ToolResult(success: true, data: anyCodable, executionTimeMs: duration)
                } else {
                    // Fallback to string
                    let str = String(data: data, encoding: .utf8) ?? "Success"
                    return ToolResult(success: true, data: .string(str), executionTimeMs: duration)
                }
            } else {
                let errorStr = String(data: data, encoding: .utf8) ?? "Unknown HTTP Error"
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
                return ToolResult(
                    success: false,
                    error: ToolError(code: .executionFailed, message: "n8n returned status \(statusCode): \(errorStr)"),
                    executionTimeMs: duration
                )
            }
        } catch {
            return ToolResult(
                success: false,
                error: ToolError(code: .executionFailed, message: "Failed to connect to n8n: \(error.localizedDescription)")
            )
        }
    }

    public func validateInput(_ input: [String: AnyCodable], forToolNamed name: String) async throws -> Bool {
        if name == "trigger_n8n_workflow" {
            return input["webhook_id"] != nil && input["payload"] != nil
        }
        return false
    }
}
