// SPDX-License-Identifier: MPL-2.0
// SPDX-FileCopyrightText: Copyright (c) 2025 Andrew Wyatt (Fewtarius) & ARES Contributors

import Foundation
import Logging

struct ServerSentEvent: Equatable, Sendable {
    let name: String
    let data: String
    let id: String?
}

/// Incremental WHATWG-style SSE field parser. URLSession supplies decoded
/// lines, while this type owns event framing and multiline `data:` handling.
struct ServerSentEventParser: Sendable {
    private var eventName = "message"
    private var dataLines: [String] = []
    private var lastEventId: String?

    mutating func consume(line rawLine: String) -> ServerSentEvent? {
        let line = rawLine.last == "\r" ? String(rawLine.dropLast()) : rawLine
        if line.isEmpty {
            return dispatch()
        }
        if line.hasPrefix(":") {
            return nil
        }

        let field: Substring
        var value: Substring
        if let separator = line.firstIndex(of: ":") {
            field = line[..<separator]
            value = line[line.index(after: separator)...]
            if value.first == " " { value = value.dropFirst() }
        } else {
            field = Substring(line)
            value = ""
        }

        switch field {
        case "event":
            eventName = String(value)
        case "data":
            dataLines.append(String(value))
        case "id":
            if !value.contains("\0") { lastEventId = String(value) }
        default:
            break
        }
        return nil
    }

    mutating func finish() -> ServerSentEvent? {
        dispatch()
    }

    private mutating func dispatch() -> ServerSentEvent? {
        defer {
            eventName = "message"
            dataLines.removeAll(keepingCapacity: true)
        }
        guard !dataLines.isEmpty else { return nil }
        return ServerSentEvent(
            name: eventName.isEmpty ? "message" : eventName,
            data: dataLines.joined(separator: "\n"),
            id: lastEventId
        )
    }
}

public enum FastAPIProviderError: Error, LocalizedError {
    case invalidBaseURL
    case httpStatus(Int)
    case malformedStartResponse
    case streamFailed(String)
    case streamEndedUnexpectedly

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "The ARES backend URL is invalid."
        case .httpStatus(let status):
            return "The ARES backend returned HTTP \(status)."
        case .malformedStartResponse:
            return "The ARES backend returned an invalid chat-start response."
        case .streamFailed(let message):
            return message
        case .streamEndedUnexpectedly:
            return "The ARES response stream ended before a terminal event."
        }
    }
}

/// Implementation of AIProviderProtocol that connects to the ARES FastAPI backend.
public final class FastAPIProvider: AIProviderProtocol, @unchecked Sendable {
    private struct StartResponse: Decodable {
        let stream_id: String
        let session_id: String
    }

    private let logger = Logger(label: "com.sam.conversation.FastAPIProvider")
    private let baseURL: URL
    private let session: URLSession

    public init(
        baseURL: String = "http://127.0.0.1:8787/api/sam-conversation",
        session: URLSession = .shared
    ) {
        self.baseURL = URL(string: baseURL) ?? URL(fileURLWithPath: "/invalid-ares-url")
        self.session = session
    }

    public func processStreamingChatCompletion(
        _ messages: [ChatMessage],
        model: String,
        temperature: Double,
        sessionId: String?
    ) async throws -> AsyncThrowingStream<ChatResponseChunk, Error> {
        guard baseURL.scheme == "http" || baseURL.scheme == "https" else {
            throw FastAPIProviderError.invalidBaseURL
        }
        let userMessage = messages.last { $0.role == "user" }?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !userMessage.isEmpty else {
            throw FastAPIProviderError.malformedStartResponse
        }

        let chatSessionId = sessionId ?? UUID().uuidString
        let payload: [String: Any] = [
            "model": model,
            "message": userMessage,
            "session_id": chatSessionId,
        ]
        let startRequest: URLRequest = {
            var request = URLRequest(url: baseURL.appendingPathComponent("chat"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
            return request
        }()
        guard startRequest.httpBody != nil else {
            throw FastAPIProviderError.malformedStartResponse
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let start = try await self.startChat(request: startRequest)
                    try await self.consumeStream(
                        streamId: start.stream_id,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    self.logger.error("FastAPI Provider error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    private func startChat(request: URLRequest) async throws -> StartResponse {
        let (data, response) = try await session.data(for: request)
        try validate(response)
        guard let result = try? JSONDecoder().decode(StartResponse.self, from: data),
              !result.stream_id.isEmpty,
              !result.session_id.isEmpty else {
            throw FastAPIProviderError.malformedStartResponse
        }
        return result
    }

    private func consumeStream(
        streamId: String,
        continuation: AsyncThrowingStream<ChatResponseChunk, Error>.Continuation
    ) async throws {
        let streamEndpoint = baseURL
            .deletingLastPathComponent()
            .appendingPathComponent("chat/stream")
        guard var components = URLComponents(url: streamEndpoint, resolvingAgainstBaseURL: false) else {
            throw FastAPIProviderError.invalidBaseURL
        }
        components.queryItems = [URLQueryItem(name: "stream_id", value: streamId)]
        guard let url = components.url else { throw FastAPIProviderError.invalidBaseURL }

        var request = URLRequest(url: url)
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        try validate(response)

        var parser = ServerSentEventParser()
        var terminalReceived = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard let event = parser.consume(line: line) else { continue }
            if try handle(event, continuation: continuation) {
                terminalReceived = true
                break
            }
        }
        if !terminalReceived, let event = parser.finish() {
            terminalReceived = try handle(event, continuation: continuation)
        }
        if !terminalReceived {
            throw FastAPIProviderError.streamEndedUnexpectedly
        }
    }

    /// Returns true when the event is terminal. Malformed and unknown
    /// observations are ignored so one bad frame cannot crash a conversation.
    private func handle(
        _ event: ServerSentEvent,
        continuation: AsyncThrowingStream<ChatResponseChunk, Error>.Continuation
    ) throws -> Bool {
        if event.name == "stream_end" { return true }
        if event.name == "cancel" { throw CancellationError() }

        guard let data = event.data.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) else {
            logger.warning("Ignoring malformed SSE JSON for event \(event.name)")
            if event.name == "error" || event.name == "apperror" {
                throw FastAPIProviderError.streamFailed("The ARES response stream failed.")
            }
            return false
        }

        if event.name == "error" || event.name == "apperror" {
            let object = value as? [String: Any]
            let message = (object?["message"] as? String)
                ?? (object?["error"] as? String)
                ?? "The ARES response stream failed."
            throw FastAPIProviderError.streamFailed(String(message.prefix(500)))
        }

        let object = value as? [String: Any]
        let isTextEvent = event.name == "token"
            || event.name == "chat_delta"
            || event.name == "interim_assistant"
        if isTextEvent {
            if event.name == "interim_assistant", object?["already_streamed"] as? Bool == true {
                return false
            }
            let text = (object?["text"] as? String) ?? (object?["delta"] as? String)
            if let text, !text.isEmpty {
                continuation.yield(ChatResponseChunk(content: text))
            }
        }
        return false
    }

    private func validate(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse else {
            throw FastAPIProviderError.httpStatus(0)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw FastAPIProviderError.httpStatus(response.statusCode)
        }
    }
}
