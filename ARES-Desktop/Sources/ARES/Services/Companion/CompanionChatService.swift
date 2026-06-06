import Foundation
import ARESCore

// MARK: - Companion Chat Service
//
// Primary: streams chat completions through the Hermes Gateway API
//   (localhost:8642/v1/chat/completions) for real-time token delivery,
//   giving the Companion full access to the Hermes agent — tools, memory,
//   skills, everything — the same engine as the TUI.
//
// Fallback: when the Gateway is unreachable, falls back to the Hermes CLI
//   (`hermes --yolo chat --query`) for a non-streaming response.

// MARK: - Result Types

struct CompanionChatTurnResult: Sendable {
    let responseText: String
    let sessionID: String
}

typealias StreamingTokenCallback = (_ partial: String, _ isFinished: Bool) -> Void

// MARK: - Session Summary (for UI list)

extension CompanionChatService {
    struct SessionSummary: Identifiable, Sendable {
        let id: String
        let title: String
        let date: Date
        let updatedAt: Date
        let messageCount: Int
        let model: String
        let provider: String
        let preview: String
    }
}

// MARK: - CompanionChatService

@MainActor
final class CompanionChatService: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = CompanionChatService()

    // MARK: - Dependencies

    private var gateway: HermesGatewayService
    private var companionConfig: CompanionConfig

    // MARK: - State

    /// The in-flight streaming Task, if any. Used for cancellation.
    private var activeStreamTask: Task<Void, Never>?

    /// In-memory conversation log for the active Companion session.
    private var activeTurns: [PersistedTurn] = []

    // MARK: - Init

    private init() {
        let config = CompanionConfig.load()
        // Auto-detect API key from ~/.hermes/.env if not in config
        let apiKey = config.apiKey.isEmpty ? CompanionConfig.readAPIKeyFromEnv() : config.apiKey
        self.companionConfig = CompanionConfig(
            gatewayURL: config.gatewayURL,
            apiKey: apiKey,
            model: config.model,
            provider: config.provider,
            maxHistoryTurns: config.maxHistoryTurns
        )
        self.gateway = HermesGatewayService(
            baseURL: URL(string: self.companionConfig.gatewayURL)!,
            apiKey: self.companionConfig.apiKey
        )
    }

    /// Re-initialize the gateway (e.g. after config change).
    func reconfigure() {
        let config = CompanionConfig.load()
        let apiKey = config.apiKey.isEmpty ? CompanionConfig.readAPIKeyFromEnv() : config.apiKey
        self.companionConfig = CompanionConfig(
            gatewayURL: config.gatewayURL,
            apiKey: apiKey,
            model: config.model,
            provider: config.provider,
            maxHistoryTurns: config.maxHistoryTurns
        )
        self.gateway = HermesGatewayService(
            baseURL: URL(string: self.companionConfig.gatewayURL)!,
            apiKey: self.companionConfig.apiKey
        )
    }

    // MARK: - Availability Check

    /// Checks whether the Hermes Gateway is reachable and responding.
    func checkAvailability() async -> Bool {
        await gateway.isReachable()
    }

    // MARK: - Send a message (streaming — primary path)

    /// Sends a user message and streams the response token-by-token through
    /// the Hermes Gateway.
    /// - Parameters:
    ///   - messages: Pre-built conversation messages including the latest user message.
    ///   - sessionID: Optional Hermes session ID for multi-turn continuity.
    ///   - onToken: Called on MainActor for each token delta. partial=accumulated text so far.
    /// - Returns: A CompanionChatTurnResult once streaming completes.
    func sendMessageStream(
        messages: [GatewayMessage],
        sessionID: String?,
        onToken: @escaping StreamingTokenCallback
    ) async throws -> CompanionChatTurnResult {
        // Cancel any in-flight stream
        activeStreamTask?.cancel()

        let stream = gateway.streamChat(
            messages: messages,
            sessionID: sessionID,
            model: companionConfig.model
        )

        // Mutable state for the stream — wrapped in a class to satisfy Sendable
        final class StreamState: @unchecked Sendable {
            var accumulated: String = ""
            var resolvedSessionID: String
            init(sessionID: String) { self.resolvedSessionID = sessionID }
        }
        let state = StreamState(sessionID: sessionID ?? "ares-gw-\(UUID().uuidString.prefix(8))")

        let streamTask = Task { @Sendable in
            do {
                for try await token in stream {
                    state.accumulated += token.content

                    let current = state.accumulated
                    await MainActor.run {
                        onToken(current, token.isFinished)
                    }

                    if token.isFinished {
                        if let sid = token.sessionID {
                            state.resolvedSessionID = sid
                        }
                        break
                    }
                }
            } catch {
                let errorMsg = "Connection error: \(error.localizedDescription)"
                await MainActor.run {
                    onToken(errorMsg, true)
                }
                state.accumulated = errorMsg
            }
        }

        activeStreamTask = streamTask
        await streamTask.value
        activeStreamTask = nil

        let finalText = state.accumulated.isEmpty ? "No response from ARES." : state.accumulated
        return CompanionChatTurnResult(responseText: finalText, sessionID: state.resolvedSessionID)
    }

    /// Cancels the active streaming request.
    func cancelStream() {
        activeStreamTask?.cancel()
        activeStreamTask = nil
    }

    // MARK: - CLI Fallback (non-streaming)

    /// Sends a message via the Hermes CLI as a non-streaming fallback.
    func sendMessage(
        _ prompt: String,
        sessionID: String?,
        model: String,
        provider: String
    ) async throws -> CompanionChatTurnResult {
        var args = [
            "--yolo", "chat",
            "--query", prompt,
            "--model", model
        ]
        if let sid = sessionID {
            args += ["--session", sid]
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["hermes"] + args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw HermesGatewayError.streamInterrupted("CLI failed with exit code \(process.terminationStatus): \(output)")
        }

        let lines = output.components(separatedBy: "\n")
        let responseText: String
        let resolvedSessionID: String

        if lines.count > 1, lines.first?.hasPrefix("session_id:") == true {
            resolvedSessionID = lines.first!
                .replacingOccurrences(of: "session_id:", with: "")
                .trimmingCharacters(in: .whitespaces)
            responseText = lines.dropFirst().joined(separator: "\n")
        } else {
            resolvedSessionID = sessionID ?? "cli-\(UUID().uuidString.prefix(8))"
            responseText = output
        }

        return CompanionChatTurnResult(responseText: responseText, sessionID: resolvedSessionID)
    }

    // MARK: - Session Persistence

    struct PersistedTurn: Codable {
        let role: String
        let content: String
        let timestamp: Date
    }

    /// Persists a chat turn to local storage (for offline history).
    func persistSession(
        turns: [PersistedTurn]? = nil,
        sessionID: String,
        model: String
    ) {
        let turnsToSave = turns ?? activeTurns
        guard !turnsToSave.isEmpty else { return }

        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("ARES/Sessions")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let filename = "\(sessionID.replacingOccurrences(of: ":", with: "-")).json"
        let url = directory.appendingPathComponent(filename)

        if let data = try? encoder.encode(turnsToSave) {
            try? data.write(to: url, options: .atomic)
        }
    }

    func appendTurn(role: String, content: String, sessionID: String, model: String) {
        activeTurns.append(PersistedTurn(role: role, content: content, timestamp: Date()))
    }

    func clearActiveTurns() {
        activeTurns = []
    }

    // MARK: - Session History (from Hermes Gateway)

    /// Lists recent sessions from the Hermes Gateway, converting them to UI summaries.
    func listSessions(limit: Int = 50) -> [SessionSummary] {
        // Synchronous wrapper — the UI calls this from a Task in AppState
        // We'll use the async version directly in refreshSessionHistory
        []
    }

    /// Async version that hits the Gateway API.
    func listSessionsAsync(limit: Int = 50) async throws -> [SessionSummary] {
        let sessions = try await gateway.listSessions(limit: limit)
        return sessions.map { session in
            SessionSummary(
                id: session.id,
                title: session.title ?? session.preview ?? "Untitled",
                date: Date(timeIntervalSince1970: session.startedAt ?? 0),
                updatedAt: Date(timeIntervalSince1970: session.lastActive ?? session.startedAt ?? 0),
                messageCount: session.messageCount ?? 0,
                model: session.model ?? "unknown",
                provider: session.source ?? "unknown",
                preview: session.preview ?? ""
            )
        }
    }

    /// Loads messages from a session via the Gateway, converting to ChatBubbles.
    func loadSessionMessages(sessionID: String) -> [ChatBubble]? {
        // Synchronous stub — use the async version
        nil
    }

    /// Async version that hits the Gateway.
    func loadSessionMessagesAsync(sessionID: String) async throws -> [ChatBubble] {
        let messages = try await gateway.sessionMessages(sessionID: sessionID)
        return messages.compactMap { msg -> ChatBubble? in
            guard let content = msg.content, !content.isEmpty else { return nil }
            let role: BubbleRole = msg.role == "user" ? .user : .assistant
            return ChatBubble(
                role: role,
                content: content,
                timestamp: Date(timeIntervalSince1970: msg.timestamp ?? 0)
            )
        }
    }
}