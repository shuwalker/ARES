import Foundation

/// A single token received from a streaming chat response.
struct StreamedToken: Sendable {
    let content: String
    let isComplete: Bool
}

/// WebSocket + SSE transport for streaming chat with local Hermes.
/// Uses URLSessionWebSocketTask for real-time /ws communication
/// and SSE parsing for /v1/chat/completions streaming.
final class WebSocketTransport: @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - SSE Streaming (HTTP /v1/chat/completions)

    /// Stream chat completions via SSE.
    /// Returns an AsyncSequence of token strings as they arrive.
    func streamChat(
        baseURL: URL,
        apiKey: String?,
        model: String,
        messages: [[String: String]],
        sessionID: String? = nil
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                var request = URLRequest(url: baseURL.appendingPathComponent("v1/chat/completions"))
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
                if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
                if let sessionID { request.setValue(sessionID, forHTTPHeaderField: "X-Hermes-Session-Id") }

                let body: [String: Any] = [
                    "model": model,
                    "messages": messages,
                    "stream": true
                ]

                do {
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        continuation.finish(throwing: TransportError.remoteFailure("HTTP \(statusCode)"))
                        return
                    }

                    var buffer = ""
                    for try await line in bytes.lines {
                        buffer += line + "\n"
                        // Parse SSE lines
                        if line.hasPrefix("data: ") {
                            let dataString = String(line.dropFirst(6))
                            if dataString == "[DONE]" {
                                continuation.yield("")
                                continuation.finish()
                                return
                            }
                            if let data = dataString.data(using: .utf8),
                               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let choices = json["choices"] as? [[String: Any]],
                               let delta = choices.first?["delta"] as? [String: Any],
                               let content = delta["content"] as? String {
                                continuation.yield(content)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - WebSocket (/ws)

    /// Connect to Hermes WebSocket for bidirectional communication.
    func connectWebSocket(baseURL: URL, apiKey: String?) async throws -> URLSessionWebSocketTask {
        var components = URLComponents()
        components.scheme = (baseURL.scheme?.lowercased() == "https") ? "wss" : "ws"
        components.host = baseURL.host ?? "localhost"
        components.port = baseURL.port ?? 8642
        components.path = "/ws"
        guard let wsURL = components.url else {
            throw TransportError.invalidConnection("Could not build WebSocket URL from \(baseURL)")
        }
        var request = URLRequest(url: wsURL)
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let task = session.webSocketTask(with: request)
        task.resume()
        // Send a ping to verify connection
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URLSessionWebSocketTask, Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: task)
                }
            }
        }
    }
}
