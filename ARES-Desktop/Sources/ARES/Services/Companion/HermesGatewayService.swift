import Foundation
import ARESCore

// MARK: - Hermes Gateway Streaming Service
//
// Streams chat completions from the Hermes Agent Gateway API
// (localhost:8642/v1/chat/completions). This connects the Companion
// directly to the full Hermes agent — tools, memory, skills, everything —
// the same engine that powers the TUI and Discord.
//
// Key features:
//   - OpenAI-compatible SSE streaming for real-time token delivery
//   - X-Hermes-Session-Id header for multi-turn session continuity
//   - Bearer token authentication via API_SERVER_KEY
//   - Session listing/creation via /api/sessions
//   - Capabilities discovery via /v1/capabilities
//   - Health checks via /health

// MARK: - Data Models

/// A single message in the OpenAI chat format.
struct GatewayMessage: Codable, Sendable {
    let role: String
    let content: String
}

/// A streaming token chunk from the gateway SSE stream.
struct GatewayStreamToken: Sendable {
    let content: String
    let isFinished: Bool
    /// The Hermes session ID returned in the final chunk (or nil mid-stream).
    let sessionID: String?
}

/// Summary of a Hermes session from /api/sessions.
struct GatewaySession: Codable, Sendable, Identifiable {
    let id: String
    let source: String?
    let model: String?
    let title: String?
    let startedAt: Double?
    let messageCount: Int?
    let preview: String?
    let lastActive: Double?

    private enum CodingKeys: String, CodingKey {
        case id, source, model, title, preview
        case startedAt = "started_at"
        case messageCount = "message_count"
        case lastActive = "last_active"
    }
}

/// A single message from a session's history.
struct GatewaySessionMessage: Codable, Sendable, Identifiable {
    let id: String
    let role: String
    let content: String?
    let timestamp: Double?

    private enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp
    }
}

// MARK: - Gateway Errors

enum HermesGatewayError: LocalizedError, Sendable {
    case notReachable
    case authenticationFailed(String)
    case httpError(statusCode: Int, body: String)
    case decodingError(String)
    case cancelled
    case streamInterrupted(String)

    var errorDescription: String? {
        switch self {
        case .notReachable: return "Hermes Gateway not reachable at the configured URL."
        case .authenticationFailed(let msg): return "Authentication failed: \(msg)"
        case .httpError(let code, let body): return "HTTP \(code): \(body)"
        case .decodingError(let msg): return "Decoding error: \(msg)"
        case .cancelled: return "Request cancelled."
        case .streamInterrupted(let msg): return "Stream interrupted: \(msg)"
        }
    }
}

// MARK: - HermesGatewayService

final class HermesGatewayService: Sendable {

    // MARK: - Configuration

    let baseURL: URL
    let apiKey: String
    let timeoutInterval: TimeInterval

    init(baseURL: URL = URL(string: "http://localhost:8642")!,
         apiKey: String,
         timeoutInterval: TimeInterval = 300) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.timeoutInterval = timeoutInterval
    }

    // MARK: - Health Check

    /// Quick health check: is the Hermes Gateway reachable?
    func isReachable() async -> Bool {
        let url = baseURL.appendingPathComponent("health")
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Streaming Chat Completion

    /// Sends a chat completion request with streaming enabled to the
    /// Hermes Gateway's OpenAI-compatible endpoint.
    ///
    /// - Parameters:
    ///   - messages: Full conversation history including the latest user message.
    ///   - sessionID: Optional Hermes session ID for multi-turn continuity
    ///     (sent as X-Hermes-Session-Id header).
    ///   - model: Model identifier (use "hermes-agent" for the full agent).
    /// - Returns: An AsyncThrowingStream of GatewayStreamToken elements.
    func streamChat(
        messages: [GatewayMessage],
        sessionID: String? = nil,
        model: String = "hermes-agent"
    ) -> AsyncThrowingStream<GatewayStreamToken, Error> {
        AsyncThrowingStream { continuation in
            Task { [baseURL, apiKey, timeoutInterval] in
                do {
                    let url = baseURL.appendingPathComponent("v1/chat/completions")

                    var body: [String: Any] = [
                        "model": model,
                        "messages": messages.map { ["role": $0.role, "content": $0.content] },
                        "stream": true
                    ]

                    let requestBody = try JSONSerialization.data(withJSONObject: body)

                    var request = URLRequest(url: url, timeoutInterval: timeoutInterval)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    if let sid = sessionID {
                        request.setValue(sid, forHTTPHeaderField: "X-Hermes-Session-Id")
                    }
                    request.httpBody = requestBody

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: HermesGatewayError.streamInterrupted("Non-HTTP response"))
                        return
                    }

                    guard httpResponse.statusCode == 200 else {
                        // Read error body for diagnostics
                        var errorBody = ""
                        for try await line in bytes.lines {
                            errorBody += line
                        }
                        continuation.finish(throwing: HermesGatewayError.httpError(
                            statusCode: httpResponse.statusCode,
                            body: String(errorBody.prefix(500))
                        ))
                        return
                    }

                    var accumulatedSessionID: String?

                    for try await line in bytes.lines {
                        // SSE lines start with "data: "
                        guard line.hasPrefix("data: ") else { continue }
                        let jsonString = String(line.dropFirst(6))

                        // Check for stream end
                        if jsonString.trimmingCharacters(in: .whitespaces) == "[DONE]" {
                            continuation.yield(GatewayStreamToken(
                                content: "",
                                isFinished: true,
                                sessionID: accumulatedSessionID
                            ))
                            continuation.finish()
                            return
                        }

                        // Parse the JSON chunk
                        guard let data = jsonString.data(using: .utf8),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = json["choices"] as? [[String: Any]],
                              let firstChoice = choices.first else {
                            continue
                        }

                        // Extract delta content
                        let delta = firstChoice["delta"] as? [String: Any]
                        let content = (delta?["content"] as? String) ?? ""

                        // Check finish_reason
                        let finishReason = firstChoice["finish_reason"] as? String
                        let isFinished = (finishReason == "stop" || finishReason == "length")

                        // Capture session ID from the final chunk
                        if isFinished, let sid = json["session_id"] as? String {
                            accumulatedSessionID = sid
                        }
                        // Also check for session_id in non-final chunks (some responses include it early)
                        if accumulatedSessionID == nil, let sid = json["session_id"] as? String {
                            accumulatedSessionID = sid
                        }

                        continuation.yield(GatewayStreamToken(
                            content: content,
                            isFinished: isFinished,
                            sessionID: isFinished ? accumulatedSessionID : nil
                        ))
                    }

                    // Stream ended without [DONE] — finish anyway
                    continuation.yield(GatewayStreamToken(content: "", isFinished: true, sessionID: accumulatedSessionID))
                    continuation.finish()

                } catch _ as CancellationError {
                    continuation.finish(throwing: HermesGatewayError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Session Management

    /// Lists recent Hermes sessions.
    func listSessions(limit: Int = 20) async throws -> [GatewaySession] {
        let url = baseURL.appendingPathComponent("api/sessions")
            .appendingQueryItems([URLQueryItem(name: "limit", value: "\(limit)")])

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw HermesGatewayError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, body: body)
        }

        // Response is { "object": "list", "data": [...] }
        struct SessionsResponse: Codable {
            let data: [GatewaySession]
        }

        do {
            let decoded = try JSONDecoder().decode(SessionsResponse.self, from: data)
            return decoded.data
        } catch {
            throw HermesGatewayError.decodingError(error.localizedDescription)
        }
    }

    /// Creates a new empty Hermes session.
    func createSession(title: String? = nil) async throws -> GatewaySession {
        let url = baseURL.appendingPathComponent("api/sessions")
        var request = URLRequest(url: url, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [:]
        if let title { body["title"] = title }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw HermesGatewayError.httpError(statusCode: statusCode, body: body)
        }

        do {
            return try JSONDecoder().decode(GatewaySession.self, from: data)
        } catch {
            throw HermesGatewayError.decodingError(error.localizedDescription)
        }
    }

    /// Fetches messages from a session.
    func sessionMessages(sessionID: String) async throws -> [GatewaySessionMessage] {
        let url = baseURL
            .appendingPathComponent("api/sessions")
            .appendingPathComponent(sessionID)
            .appendingPathComponent("messages")

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw HermesGatewayError.httpError(statusCode: statusCode, body: body)
        }

        struct MessagesResponse: Codable {
            let data: [GatewaySessionMessage]
        }

        do {
            let decoded = try JSONDecoder().decode(MessagesResponse.self, from: data)
            return decoded.data
        } catch {
            throw HermesGatewayError.decodingError(error.localizedDescription)
        }
    }
}

// MARK: - URL Query Items Helper

private extension URL {
    func appendingQueryItems(_ items: [URLQueryItem]) -> URL {
        guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.queryItems = (components.queryItems ?? []) + items
        return components.url ?? self
    }
}