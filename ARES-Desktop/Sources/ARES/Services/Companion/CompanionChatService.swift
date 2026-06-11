import Foundation
import ARESCore
import os
import SwiftData

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

    /// Exposed so that HermesAgentBrain (and other services) can access the
    /// memory store for reflection persistence and retrieval.
    var currentMemoryStore: (any MemoryStore)?

    // MARK: - State

    /// The in-flight streaming Task, if any. Used for cancellation.
    private var activeStreamTask: Task<Void, Never>?

    /// In-memory conversation log for the active Companion session.
    private var activeTurns: [PersistedTurn] = []

    // MARK: - SwiftData Container
    private lazy var container: ModelContainer? = {
        do {
            return try ModelContainer(for: SessionModel.self, MessageModel.self)
        } catch {
            logger.error("Failed to create SwiftData container: \\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }()

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
    ///   - gatewayOverride: Optional gateway to route this call through instead of the
    ///     service's configured gateway (used by GatewayBrain to bring its own provider).
    ///   - modelOverride: Optional model name overriding the configured companion model.
    ///   - onToken: Called on MainActor for each token delta. partial=accumulated text so far.
    /// - Returns: A CompanionChatTurnResult once streaming completes.
    func sendMessageStream(
        messages: [GatewayMessage],
        sessionID: String?,
        gateway gatewayOverride: (any GatewayProvider)? = nil,
        modelOverride: String? = nil,
        onToken: @escaping StreamingTokenCallback
    ) async throws -> CompanionChatTurnResult {
        // Cancel any in-flight stream
        activeStreamTask?.cancel()

        // Build conversation context from GatewayMessage to Message
        var conversation = messages.map { msg in
            Message(
                role: msg.role == "user" ? .user : (msg.role == "assistant" ? .assistant : .system),
                content: msg.content
            )
        }

        // Resolve gateway/model for this call. Per-call overrides let brains
        // (e.g. GatewayBrain) route through their own provider instead of the
        // service's configured one.
        let gateway = gatewayOverride ?? self.gateway
        let model = modelOverride ?? companionConfig.model

        // Agent loop: offer local tools to tool-capable gateways.
        // Hermes runs its own agent loop server-side and does not advertise
        // the "tools" capability here, so it streams straight through.
        let availableTools = await ToolRouter.shared.availableTools()
        let useTools = !availableTools.isEmpty && gateway.capabilities.contains("tools")
        let maxToolRounds = 8

        // Mutable state for the stream — wrapped in a class to satisfy Sendable
        final class StreamState: @unchecked Sendable {
            var transcript: String = ""        // everything shown to the user across rounds
            var roundText: String = ""         // model text in the current round
            var toolCalls: [ToolCall] = []     // tool calls requested in the current round
            var resolvedSessionID: String
            var tokenCount: Int?
            init(sessionID: String) { self.resolvedSessionID = sessionID }
        }
        let state = StreamState(sessionID: sessionID ?? "ares-gw-\(UUID().uuidString.prefix(8))")

        for round in 1...maxToolRounds {
            let context = ConversationContext(
                messages: conversation,
                sessionID: sessionID,
                model: model
            )

            let stream = gateway.promptStream(
                "",
                context: context,
                options: GatewayOptions(tools: useTools ? availableTools : nil)
            )

            state.roundText = ""
            state.toolCalls = []

            let streamTask = Task { @Sendable in
                for await token in stream {
                    state.roundText += token.text
                    if let calls = token.toolCalls {
                        state.toolCalls.append(contentsOf: calls)
                    }

                    let current = state.transcript + state.roundText
                    let isFinishedForUI = token.isFinal && state.toolCalls.isEmpty
                    await MainActor.run {
                        onToken(current, isFinishedForUI)
                    }

                    if token.isFinal {
                        break
                    }
                }
            }

            activeStreamTask = streamTask
            await streamTask.value
            activeStreamTask = nil

            // No tool calls -> this round's text is the final answer.
            if state.toolCalls.isEmpty {
                state.transcript += state.roundText
                break
            }

            // Tool round: record the model turn, execute each call (approval
            // is enforced inside ToolRouter), and feed results back.
            state.transcript += state.roundText
            let callDescriptions = state.toolCalls
                .map { "\($0.toolName)(\(ToolJSON.dictionary(from: $0.input)))" }
                .joined(separator: ", ")
            conversation.append(Message(
                role: .assistant,
                content: state.roundText.isEmpty
                    ? "[calling tools: \(callDescriptions)]"
                    : state.roundText + "\n[calling tools: \(callDescriptions)]"
            ))

            for call in state.toolCalls {
                let displayName = call.toolName
                    .replacingOccurrences(of: ToolRouter.namespaceSeparator, with: " · ")
                state.transcript += "\n\n⚙️ \(displayName)…"
                let progressSoFar = state.transcript
                await MainActor.run { onToken(progressSoFar, false) }

                let result = await ToolRouter.shared.execute(call)

                let resultText: String
                if result.success {
                    state.transcript += " ✅"
                    if let data = result.data {
                        resultText = String(String(describing: ToolJSON.any(from: data)).prefix(4000))
                    } else {
                        resultText = "(no output)"
                    }
                } else {
                    state.transcript += " ❌"
                    resultText = "ERROR: \(result.error?.message ?? "unknown failure")"
                }
                let progressAfter = state.transcript
                await MainActor.run { onToken(progressAfter, false) }

                conversation.append(Message(
                    role: .user,
                    content: "[tool result for \(call.toolName)]: \(resultText)"
                ))
            }
            state.transcript += "\n\n"

            // Out of rounds: surface that we stopped rather than looping forever.
            if round == maxToolRounds {
                state.transcript += "⚠️ Stopped after \(maxToolRounds) tool rounds without a final answer.\n"
                let finalProgress = state.transcript
                await MainActor.run { onToken(finalProgress, true) }
            }
        }

        let finalText = state.transcript.isEmpty ? "No response from ARES." : state.transcript
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
        guard let container = container else { return }
        let context = ModelContext(container)
        
        let turnsToSave = turns ?? activeTurns
        guard !turnsToSave.isEmpty else { return }

        // Fetch or create session
        let fetchDescriptor = FetchDescriptor<SessionModel>(predicate: #Predicate { $0.id == sessionID })
        let existingSessions = try context.fetch(fetchDescriptor)
        
        let sessionModel: SessionModel
        if let existing = existingSessions.first {
            sessionModel = existing
            sessionModel.updatedAt = Date()
            sessionModel.model = model
            sessionModel.provider = companionConfig.provider
        } else {
            let title = turnsToSave.first(where: { $0.role == "user" })?.content.prefix(30).description ?? "New Session"
            sessionModel = SessionModel(
                id: sessionID,
                title: title,
                startedAt: turnsToSave.first?.timestamp ?? Date(),
                updatedAt: Date(),
                model: model,
                provider: companionConfig.provider
            )
            context.insert(sessionModel)
        }
        
        // Add new messages that aren't already in the session
        // For simplicity in this demo, we clear and re-add or just add the newest ones.
        // Actually, since activeTurns grows, let's just sync the array.
        let existingCount = sessionModel.messages.count
        if turnsToSave.count > existingCount {
            let newTurns = turnsToSave.dropFirst(existingCount)
            for turn in newTurns {
                let msgModel = MessageModel(role: turn.role, content: turn.content, timestamp: turn.timestamp, session: sessionModel)
                context.insert(msgModel)
                sessionModel.messages.append(msgModel)
            }
        }
        
        try context.save()
    }

    func appendTurn(role: String, content: String, sessionID: String, model: String) {
        activeTurns.append(PersistedTurn(role: role, content: content, timestamp: Date()))
    }

    func clearActiveTurns() {
        activeTurns = []
    }

    // MARK: - Session History (from Hermes Gateway)

    /// Lists recent sessions from the Hermes Gateway, converting them to UI summaries.
    /// NOTE: This synchronous version exists only for legacy callers. New code
    /// should use `listSessionsAsync()` which calls the real gateway.
    func listSessions(limit: Int = 50) -> [SessionSummary] {
        // Synchronous wrapper — will block the calling thread.
        // Prefer `listSessionsAsync()` for UI code.
        let semaphore = DispatchSemaphore(value: 0)
        var result: [SessionSummary] = []
        Task {
            do {
                result = try await listSessionsAsync(limit: limit)
            } catch {
                logger.error("Sync listSessions failed: \(error.localizedDescription, privacy: .public)")
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        return result
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
    /// NOTE: This synchronous version exists only for legacy callers. New code
    /// should use `loadSessionMessagesAsync()` which reads from real storage.
    func loadSessionMessages(sessionID: String) -> [ChatBubble]? {
        // Synchronous wrapper — will block the calling thread.
        // Prefer `loadSessionMessagesAsync()` for UI code.
        let semaphore = DispatchSemaphore(value: 0)
        var result: [ChatBubble]? = nil
        Task {
            do {
                result = try await loadSessionMessagesAsync(sessionID: sessionID)
            } catch {
                logger.error("Sync loadSessionMessages failed: \(error.localizedDescription, privacy: .public)")
            }
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
        return result
    }

    /// Loads messages from a session async.
    func loadSessionMessagesAsync(sessionID: String) async throws -> [ChatBubble] {
        guard let container = container else { return [] }
        let context = ModelContext(container)
        
        let fetchDescriptor = FetchDescriptor<SessionModel>(predicate: #Predicate { $0.id == sessionID })
        guard let sessionModel = try context.fetch(fetchDescriptor).first else {
            return []
        }
        
        let sortedMessages = sessionModel.messages.sorted(by: { $0.timestamp < $1.timestamp })
        
        // Populate activeTurns so future appends work seamlessly
        activeTurns = sortedMessages.map { PersistedTurn(role: $0.role, content: $0.content, timestamp: $0.timestamp) }
        
        return sortedMessages.map { msg in
            ChatBubble(
                role: msg.role == "user" ? .user : .assistant,
                content: msg.content,
                timestamp: msg.timestamp
            )
        }
    }
}
