import Foundation
import ARESCore
import os

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
    let tokenCount: Int?
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

    private var gateway: any GatewayProvider
    private var companionConfig: CompanionConfig
    private let logger = Logger(subsystem: "com.ares", category: "CompanionChat")

    // MARK: - State

    /// The in-flight streaming Task, if any. Used for cancellation.
    private var activeStreamTask: Task<Void, Never>?

    /// In-memory conversation log for the active Companion session.
    private var activeTurns: [PersistedTurn] = []

    // MARK: - Init

    private init() {
        let config = CompanionConfig.load()
        let apiKey = config.apiKey.isEmpty ? CompanionConfig.readAPIKeyFromEnv() : config.apiKey
        self.companionConfig = CompanionConfig(
            gatewayURL: config.gatewayURL,
            apiKey: apiKey,
            model: config.model,
            provider: config.provider,
            maxHistoryTurns: config.maxHistoryTurns
        )
        // Default to Ollama in dev, Hermes in prod if configured
        if config.provider == "hermes" || !config.gatewayURL.contains("11434") {
            self.gateway = HermesGatewayProvider(
                baseURL: URL(string: config.gatewayURL) ?? URL(string: "http://localhost:8642")!,
                apiKey: apiKey
            )
        } else {
            self.gateway = OllamaGatewayProvider(
                baseURL: URL(string: config.gatewayURL) ?? URL(string: "http://localhost:11434")!
            )
        }
    }

    /// Re-initialize the gateway (e.g. after config change or model selection).
    func reconfigure(provider: String = "ollama", gatewayURL: String = "http://localhost:11434") {
        let config = CompanionConfig.load()
        let apiKey = config.apiKey.isEmpty ? CompanionConfig.readAPIKeyFromEnv() : config.apiKey
        self.companionConfig = CompanionConfig(
            gatewayURL: gatewayURL,
            apiKey: apiKey,
            model: config.model,
            provider: provider,
            maxHistoryTurns: config.maxHistoryTurns
        )
        // Switch gateway based on provider
        if provider == "hermes" {
            self.gateway = HermesGatewayProvider(
                baseURL: URL(string: gatewayURL) ?? URL(string: "http://localhost:8642")!,
                apiKey: apiKey
            )
        } else {
            self.gateway = OllamaGatewayProvider(
                baseURL: URL(string: gatewayURL) ?? URL(string: "http://localhost:11434")!
            )
        }
    }

    /// Switches the active gateway provider.
    func switchProvider(_ provider: any GatewayProvider) {
        self.gateway = provider
    }

    // MARK: - Availability Check

    /// Checks whether the current gateway is reachable and responding.
    func checkAvailability() async -> Bool {
        do {
            let health = try await gateway.healthCheck()
            return health.isHealthy
        } catch {
            logger.error("Health check failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Send a message (streaming — primary path)

    /// Sends a user message and streams the response token-by-token through the current gateway.
    /// - Parameters:
    ///   - messages: Pre-built conversation messages including the latest user message.
    ///   - sessionID: Optional session ID for multi-turn continuity.
    ///   - onToken: Called on MainActor for each token delta. partial=accumulated text so far.
    /// - Returns: A CompanionChatTurnResult once streaming completes.
    func sendMessageStream(
        messages: [GatewayMessage],
        sessionID: String?,
        onToken: @escaping StreamingTokenCallback
    ) async throws -> CompanionChatTurnResult {
        // Cancel any in-flight stream
        activeStreamTask?.cancel()

        // Build conversation context from GatewayMessage to Message
        let contextMessages = messages.map { msg in
            Message(
                role: msg.role == "user" ? .user : (msg.role == "assistant" ? .assistant : .system),
                content: msg.content
            )
        }

        let context = ConversationContext(
            messages: contextMessages,
            sessionID: sessionID,
            model: companionConfig.model
        )

        let stream = gateway.promptStream(
            "",
            context: context,
            options: GatewayOptions()
        )

        // Mutable state for the stream — wrapped in a class to satisfy Sendable
        final class StreamState: @unchecked Sendable {
            var accumulated: String = ""
            var resolvedSessionID: String
            var tokenCount: Int?
            init(sessionID: String) { self.resolvedSessionID = sessionID }
        }
        let state = StreamState(sessionID: sessionID ?? "ares-gw-\(UUID().uuidString.prefix(8))")

        let streamTask = Task { @Sendable in
            for await token in stream {
                state.accumulated += token.text

                let current = state.accumulated
                await MainActor.run {
                    onToken(current, token.isFinal)
                }

                if token.isFinal {
                    break
                }
            }
        }

        activeStreamTask = streamTask
        await streamTask.value
        activeStreamTask = nil

        let finalText = state.accumulated.isEmpty ? "No response from ARES." : state.accumulated
        return CompanionChatTurnResult(responseText: finalText, sessionID: state.resolvedSessionID, tokenCount: state.tokenCount)
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

        if lines.count > 1, let firstLine = lines.first, firstLine.hasPrefix("session_id:") {
            resolvedSessionID = firstLine
                .replacingOccurrences(of: "session_id:", with: "")
                .trimmingCharacters(in: .whitespaces)
            responseText = lines.dropFirst().joined(separator: "\n")
        } else {
            resolvedSessionID = sessionID ?? "cli-\(UUID().uuidString.prefix(8))"
            responseText = output
        }

        return CompanionChatTurnResult(responseText: responseText, sessionID: resolvedSessionID, tokenCount: nil)
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
    ) throws {
        let turnsToSave = turns ?? activeTurns
        guard !turnsToSave.isEmpty else { return }

        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            logger.error("Could not locate Application Support directory; skipping session persist for \(sessionID, privacy: .public)")
            return
        }
        let directory = appSupport.appendingPathComponent("ARES/Sessions")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let filename = "\(sessionID.replacingOccurrences(of: ":", with: "-")).json"
        let url = directory.appendingPathComponent(filename)

        let data = try encoder.encode(turnsToSave)
        try data.write(to: url, options: .atomic)
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

    /// Lists recent sessions via the current gateway.
    func listSessionsAsync(limit: Int = 50) async throws -> [SessionSummary] {
        // Delegate to the gateway — Hermes returns sessions, Ollama returns empty
        let sessions = try await gateway.sessionList(limit: limit)
        return sessions.map { session in
            let updatedAt = session.lastActive?.dateValue ??
                session.startedAt?.dateValue ??
                Date()
            return SessionSummary(
                id: session.id,
                title: session.resolvedTitle,
                date: session.startedAt?.dateValue ?? updatedAt,
                updatedAt: updatedAt,
                messageCount: session.messageCount ?? 0,
                model: session.displayModel ?? "unknown",
                provider: gateway.identifier,
                preview: session.preview ?? ""
            )
        }
    }

    /// Loads messages from a session (Hermes only).
    func loadSessionMessages(sessionID: String) -> [ChatBubble]? {
        // Synchronous stub — use the async version
        nil
    }

    /// Loads messages from a session async.
    func loadSessionMessagesAsync(sessionID: String) async throws -> [ChatBubble] {
        guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            logger.error("Could not locate Application Support directory; cannot load session \(sessionID, privacy: .public)")
            throw HermesGatewayError.streamInterrupted("Application Support directory unavailable")
        }
        let directory = appSupport.appendingPathComponent("ARES/Sessions")
        let filename = "\(sessionID.replacingOccurrences(of: ":", with: "-")).json"
        let url = directory.appendingPathComponent(filename)
        
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let turns = try decoder.decode([PersistedTurn].self, from: data)
        
        return turns.map { turn in
            ChatBubble(
                role: turn.role == "user" ? .user : .assistant,
                content: turn.content,
                timestamp: turn.timestamp
            )
        }
    }
}
