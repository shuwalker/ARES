import Foundation
import SwiftUI
import ARESCore

// MARK: - App State

@MainActor
final class ARESAppState: ObservableObject {
    // MARK: - Bootstrap state
    @Published var hasBootstrapped: Bool = UserDefaults.standard.bool(forKey: "ARES.hasBootstrapped") {
        didSet { UserDefaults.standard.set(hasBootstrapped, forKey: "ARES.hasBootstrapped") }
    }

    @Published var dependencies: [ARESDependency: DependencyStatus] = [:]
    @Published var isScanning = false
    @Published var isInstalling = false
    @Published var installError: String?

    // MARK: - Tab navigation
    @Published var selectedTab: ARESTab = .companion

    // MARK: - Companion state
    @Published var companionGreeting: String = ""
    @Published var selfModelContent: String = ""
    @Published var voiceState: VoiceState = .idle
    @Published var skillCount: Int = 0
    @Published var sessionCount: Int = 0
    @Published var memoryPercent: Int = 0
    @Published var hermesRunning: Bool = false
    @Published var hermesGatewayURL: String = "http://localhost:8642"
    @Published var activeOfficeAgents: Int = 0

    /// Sum of `costUSD` on all chat bubbles newer than 24h, formatted for the stats card.
    /// Returns "0.00" when no cost data has been recorded yet (gateway sends `nil` until usage is reported).
    var formatted24hCost: String {
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let total = chatMessages
            .filter { $0.timestamp >= cutoff }
            .compactMap { $0.costUSD }
            .reduce(0.0, +)
        return String(format: "%.2f", total)
    }

    // MARK: - Chat state
    @Published var chatMessages: [ChatBubble] = []
    @Published var chatInput: String = ""
    @Published var isChatProcessing: Bool = false
    @Published var activeChatSessionID: String? = nil
    @Published var autoSpeakNextResponse: Bool = false
    @Published var companionConfig: CompanionConfig = CompanionConfig.load()

    // MARK: - Reference state
    @Published var attachedReferences: [AttachedReference] = []
    @Published var showReferencePicker: Bool = false

    // MARK: - History state
    @Published var sessionHistory: [CompanionChatService.SessionSummary] = []
    @Published var viewingHistoricalSessionID: String? = nil
    @Published var historicalMessages: [ChatBubble] = []
    @Published var isLoadingHistory: Bool = false

    /// True when the user is viewing a historical session (chat input disabled).
    var isViewingHistory: Bool { viewingHistoricalSessionID != nil }

    // MARK: - Office state
    @Published var officeAgents: [AgentCard] = []
    @Published var officeAgentCount: Int = 0

    // MARK: - Source readers (cross-tool)
    /// Readers for Claude Code, Gemini CLI, Odysseus, Hermes — used by the
    /// reference picker to attach session context to ARES chat messages.
    let sourceReaders: [any SourceReader] = [
        ClaudeSessionReader(),
        GeminiSessionReader(),
        OdysseusSessionReader(),
        HermesSessionReader()
    ]

    // MARK: - Backend protocols (injected at startup)
    var embodiment: any Embodiment
    var perceiver: any Perceiver
    var memory: any MemoryStore
    var voice: any VoiceEngine
    var brain: any ReasoningBrain
    var identity: any Identity
    var mimicry: any Mimicry
    var world: any WorldPerception
    var eventBus: any EventBus
    var workflow: any Workflow
    var scheduler: any Scheduler

    private let scanner = DependencyScanner()
    private let installer = DependencyInstaller()
    private let chatService = CompanionChatService.shared
    private var refreshTimer: Timer?

    /// Designated initializer accepting a full BackendStack.
    init(stack: BackendStack) {
        self.embodiment = stack.embodiment
        self.perceiver = stack.perceiver
        self.memory = stack.memory
        self.voice = stack.voice
        self.brain = stack.brain
        self.identity = stack.identity
        self.mimicry = stack.mimicry
        self.world = stack.world
        self.eventBus = stack.eventBus
        self.workflow = stack.workflow
        self.scheduler = stack.scheduler
        self.hasBootstrapped = UserDefaults.standard.bool(forKey: "ARES.hasBootstrapped")
        refreshLiveStats()
    }

    /// Convenience initializer that resolves backends from environment.
    /// Routes through BackendBuilder — no silent dummy injection.
    convenience init() {
        let backends = resolveBackends(environmentFromLaunchArgs())
        self.init(stack: backends)
        print("⚠️  [ARESAppState] Convenience init() used — backends resolved from ARES_ENV.")
    }

    // MARK: - Bootstrap actions

    func scanDependencies() async {
        isScanning = true
        defer { isScanning = false }

        for dep in ARESDependency.allCases {
            dependencies[dep] = .checking
        }

        let results = await scanner.scanAll()
        for result in results {
            dependencies[result.dependency] = result.status
        }
    }

    func installMissing() async {
        isInstalling = true
        installError = nil
        defer { isInstalling = false }

        for (dep, status) in dependencies {
            guard status == .missing, !dep.installMethod.isManual else { continue }
            do {
                try await installer.install(dep)
                dependencies[dep] = .installed
            } catch {
                dependencies[dep] = .failed(error.localizedDescription)
                installError = error.localizedDescription
            }
        }
    }

    func completeBootstrap() {
        hasBootstrapped = true
    }

    // MARK: - Live stats

    func refreshLiveStats() {
        // Skill count from file system
        let skillsDir = ARESEnvironment.skillsDirectory.path
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: skillsDir) {
            skillCount = contents.count
        }

        // Memory percent from file
        let memPath = ARESEnvironment.memoryFilePath.path
        if let memContent = try? String(contentsOfFile: memPath, encoding: .utf8) {
            // Parse capacity percentage from memory file header
            if let capLine = memContent.components(separatedBy: "\n").first(where: { $0.contains("%") }) {
                if let pctStr = capLine.components(separatedBy: "[").last?.components(separatedBy: "%").first,
                   let pct = Int(pctStr.trimmingCharacters(in: .whitespaces)) {
                    memoryPercent = pct
                } else {
                    memoryPercent = 94
                }
            } else {
                memoryPercent = 94
            }
        } else {
            memoryPercent = 94
        }

        // Hermes health check via HTTP
        checkHermesHealth()

        // Session count from session DB
        refreshSessionCount()

        // Office agents
        refreshOfficeAgents()

        // Schedule periodic refresh
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkHermesHealth()
            }
        }
    }

    private func checkHermesHealth() {
        Task {
            if let url = URL(string: "\(hermesGatewayURL)/health") {
                var req = URLRequest(url: url, timeoutInterval: 3)
                req.cachePolicy = .reloadIgnoringLocalCacheData
                do {
                    let (_, response) = try await URLSession.shared.data(for: req)
                    hermesRunning = (response as? HTTPURLResponse)?.statusCode == 200
                } catch {
                    // Fallback: try WebUI
                    if let webURL = URL(string: "http://localhost:9119") {
                        var webReq = URLRequest(url: webURL, timeoutInterval: 2)
                        webReq.cachePolicy = .reloadIgnoringLocalCacheData
                        do {
                            let (_, webResp) = try await URLSession.shared.data(for: webReq)
                            hermesRunning = (webResp as? HTTPURLResponse)?.statusCode == 200
                        } catch {
                            hermesRunning = false
                        }
                    } else {
                        hermesRunning = false
                    }
                }
            }
        }
    }

    private func refreshSessionCount() {
        // Count ARES companion sessions on disk
        let aresSessionsDir = ARESEnvironment.sessionsDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: aresSessionsDir.path) {
            sessionCount = contents.filter { $0.hasSuffix(".json") }.count
        }
        if sessionCount == 0 {
            sessionCount = 4 // fallback
        }
    }

    private func refreshOfficeAgents() {
        // Discover active agents from Hermes
        // For now: Hermes itself + any detected sub-processes
        var agents: [AgentCard] = []

        // Hermes agent
        if hermesRunning {
            agents.append(AgentCard(
                name: "Hermes",
                role: "Reasoning Engine",
                status: .active,
                detail: "Primary cognition agent"
            ))
        }

        // Check for Ollama
        let ollamaCheck = Process()
        ollamaCheck.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        ollamaCheck.arguments = ["-x", "ollama"]
        let pipe = Pipe()
        ollamaCheck.standardOutput = pipe
        ollamaCheck.standardError = FileHandle.nullDevice
        try? ollamaCheck.run()
        ollamaCheck.waitUntilExit()
        if ollamaCheck.terminationStatus == 0 {
            agents.append(AgentCard(
                name: "Ollama",
                role: "ML Engine",
                status: .active,
                detail: "Local model inference"
            ))
        }

        // SearXNG
        let sxCheck = Process()
        sxCheck.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        sxCheck.arguments = ["-f", "searxng"]
        let sxPipe = Pipe()
        sxCheck.standardOutput = sxPipe
        sxCheck.standardError = FileHandle.nullDevice
        try? sxCheck.run()
        sxCheck.waitUntilExit()
        if sxCheck.terminationStatus == 0 {
            agents.append(AgentCard(
                name: "SearXNG",
                role: "Research",
                status: .active,
                detail: "Self-hosted search engine"
            ))
        }

        officeAgents = agents
        officeAgentCount = agents.count
    }

    // MARK: - Chat

    /// Sends the current chat input to Hermes via CompanionChatService and
    /// appends the response. Persists the session to the configured memory directory.
    /// If references are attached, prepends a short reference context to the
    /// prompt so the model knows about the cited source(s).
    func sendChat() {
        let text = chatInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isChatProcessing, !isViewingHistory else { return }

        // Capture references before clearing the attachment bar
        let refs = attachedReferences

        // Build display text (what the user typed) and prompt text (what the model sees).
        // The model gets reference context prepended; the UI shows the raw user text.
        let displayText = text
        let promptText = Self.buildPromptWithReferences(text: text, references: refs)

        // Append user bubble with the display text (raw, without preamble) so UI is clean
        let userBubble = ChatBubble(role: .user, content: displayText, references: refs.isEmpty ? nil : refs)
        chatMessages.append(userBubble)
        chatInput = ""
        attachedReferences = []
        isChatProcessing = true
        voiceState = .thinking

        // Create a placeholder streaming bubble for the assistant's response
        let streamingBubbleID = UUID()
        let startedAt = Date()
        var streamingBubble = ChatBubble(
            role: .assistant,
            content: "",
            references: refs.isEmpty ? nil : refs,
            isStreaming: true,
            startedAt: startedAt
        )
        streamingBubble.id = streamingBubbleID
        chatMessages.append(streamingBubble)

        // Keep a snapshot of the full conversation history for context (before streaming bubble)
        let conversationHistory = chatMessages.filter { !$0.isStreaming }

        // Ensure we have a session ID before calling the brain
        if activeChatSessionID == nil {
            activeChatSessionID = "ares-\(UUID().uuidString.prefix(8))"
        }
        let sessionID = activeChatSessionID

        Task {
            do {
                let contextMessages = conversationHistory.map { bubble in
                    Message(
                        role: bubble.role == .user ? .user : .assistant,
                        content: bubble.content
                    )
                }
                let context = ConversationContext(
                    messages: contextMessages,
                    sessionID: sessionID,
                    model: companionConfig.model
                )

                let throttle = StreamingThrottle { [weak self] bubbleID, text in
                    guard let self else { return }
                    if let idx = self.chatMessages.firstIndex(where: { $0.id == bubbleID }) {
                        self.chatMessages[idx].content = text
                    }
                }

                let response = try await brain.respond(
                    to: promptText,
                    context: context,
                    onToken: { [weak self] partial, isFinished in
                        Task { @MainActor in
                            guard let self else { return }
                            throttle.enqueue(bubbleID: streamingBubbleID, text: partial)
                            if isFinished {
                                throttle.cancel()
                                if let idx = self.chatMessages.firstIndex(where: { $0.id == streamingBubbleID }) {
                                    self.chatMessages[idx].isStreaming = false
                                }
                                if self.autoSpeakNextResponse {
                                    self.autoSpeakNextResponse = false
                                    let prosody = Prosody(timestamp: Date(), energy: 0.8, pitch: 120, rate: 0.9)
                                    Task {
                                        do {
                                            _ = try await self.voice.synthesize(text: partial, prosody: prosody)
                                        } catch {
                                            print("⚠️ [ARESAppState] TTS Error: \(error)")
                                        }
                                    }
                                }
                            }
                        }
                    }
                )

                await MainActor.run {
                    throttle.cancel()
                    if let idx = chatMessages.firstIndex(where: { $0.id == streamingBubbleID }) {
                        chatMessages[idx].isStreaming = false
                        chatMessages[idx].latencySeconds = Date().timeIntervalSince(startedAt)
                        if chatMessages[idx].content.isEmpty {
                            chatMessages[idx].content = response.isEmpty ? "No response from ARES." : response
                        }
                    }
                    isChatProcessing = false
                    voiceState = .idle
                    persistChatTurn(userText: displayText, assistantText: chatMessages.last?.content ?? response, refs: refs)
                }
            } catch {
                await MainActor.run {
                    if let idx = chatMessages.firstIndex(where: { $0.id == streamingBubbleID }) {
                        chatMessages[idx].content = "ARES backend error: \(error.localizedDescription)"
                        chatMessages[idx].isStreaming = false
                        chatMessages[idx].latencySeconds = Date().timeIntervalSince(startedAt)
                    }
                    isChatProcessing = false
                    voiceState = .idle
                }
            }
        }
    }

    /// CLI fallback when Ollama is not reachable. Replaces the streaming bubble.
    private func fallbackToCLI(displayText: String, promptText: String, sessionID: String?, refs: [AttachedReference], streamingBubbleID: UUID, startedAt: Date) {
        Task {
            do {
                let result = try await chatService.sendMessage(
                    promptText,
                    sessionID: sessionID,
                    model: companionConfig.model,
                    provider: companionConfig.provider
                )
                await MainActor.run {
                    if let idx = chatMessages.firstIndex(where: { $0.id == streamingBubbleID }) {
                        chatMessages[idx].content = result.responseText.isEmpty ? "No response from ARES." : result.responseText
                        chatMessages[idx].isStreaming = false
                        chatMessages[idx].latencySeconds = Date().timeIntervalSince(startedAt)
                    }
                    activeChatSessionID = result.sessionID
                    isChatProcessing = false
                    voiceState = .idle
                    persistChatTurn(userText: displayText, assistantText: result.responseText, refs: refs)
                }
            } catch {
                await MainActor.run {
                    if let idx = chatMessages.firstIndex(where: { $0.id == streamingBubbleID }) {
                        chatMessages[idx].content = "ARES backend error: \(error.localizedDescription)"
                        chatMessages[idx].isStreaming = false
                        // Still record latency even on error — the attempt took real time
                        chatMessages[idx].latencySeconds = Date().timeIntervalSince(startedAt)
                    }
                    isChatProcessing = false
                    voiceState = .idle
                }
            }
        }
    }

    /// Persists the user+assistant turn and refreshes the history sidebar.
    private func persistChatTurn(userText: String, assistantText: String, refs: [AttachedReference]) {
        let sid = activeChatSessionID ?? "ares-local-\(UUID().uuidString)"

        // Persist locally as backup (Gateway manages its own sessions)
        chatService.appendTurn(role: "user", content: userText, sessionID: sid, model: companionConfig.model)
        chatService.appendTurn(role: "assistant", content: assistantText, sessionID: sid, model: companionConfig.model)
        do {
            try chatService.persistSession(sessionID: sid, model: companionConfig.model)
        } catch {
            let errorBubble = ChatBubble(
                role: .assistant,
                content: "⚠️ System Error: Unable to save history. Disk may be full or permissions denied.\nDetails: \(error.localizedDescription)",
                timestamp: Date()
            )
            chatMessages.append(errorBubble)
        }
        refreshSessionHistory()
    }

    /// Cancels the in-flight streaming request.
    func cancelStreaming() {
        chatService.cancelStream()
        // Finalize any streaming bubble
        if let idx = chatMessages.lastIndex(where: { $0.isStreaming }) {
            chatMessages[idx].isStreaming = false
            if chatMessages[idx].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                chatMessages[idx].content = "(Cancelled)"
            }
        }
        isChatProcessing = false
        voiceState = .idle
    }

    /// Builds a prompt string that includes short source reference context
    /// before the user's message. The UI shows the references as chips too.
    private static func buildPromptWithReferences(text: String, references: [AttachedReference]) -> String {
        guard !references.isEmpty else { return text }

        var preamble = ""
        for ref in references {
            preamble += "[Reference from \(ref.sourceName) session \"\(ref.title ?? ref.sessionId)\""
            if let ts = ref.timestamp {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                preamble += ", \(formatter.string(from: ts))"
            }
            preamble += "]\n"
            if let snippet = ref.snippet, !snippet.isEmpty {
                let truncated = String(snippet.prefix(500))
                preamble += "\(truncated)\n"
            }
            preamble += "\n"
        }
        return preamble + text
    }

    // MARK: - Reference attachments

    /// Load messages from a source session by its source-prefixed ID
    /// (e.g. "claude_code:abc123"). Returns empty array if the reader
    /// can't find the session.
    func loadSourceMessages(sessionId: String, source: String) -> [SessionMessage] {
        guard let reader = sourceReaders.first(where: { $0.sourceName == source }) else { return [] }
        return (try? reader.loadMessages(forSessionId: sessionId)) ?? []
    }

    /// Attach a session as a reference. Loads the first few messages to build
    /// a snippet so the model has concrete context in the prompt preamble.
    func attachReference(session: UnifiedSession) {
        let messages = loadSourceMessages(sessionId: session.id, source: session.source)

        let snippet: String?
        if messages.isEmpty {
            snippet = nil
        } else {
            let firstFew = messages.prefix(5).map { msg -> String in
                let roleLabel = (msg.role == .user) ? "User" : "Assistant"
                let content = msg.content ?? ""
                return "\(roleLabel): \(String(content.prefix(100)))"
            }.joined(separator: "\n")
            snippet = firstFew.isEmpty ? nil : firstFew
        }

        let displayName = displayName(for: session.source)

        let ref = AttachedReference(
            sessionId: session.id,
            sourceName: displayName,
            title: session.title ?? session.id,
            timestamp: session.updatedAt ?? session.startedAt,
            snippet: snippet
        )
        attachedReferences.append(ref)
    }

    /// Remove an attached reference by its id.
    func removeReference(_ ref: AttachedReference) {
        attachedReferences.removeAll { $0.id == ref.id }
    }

    private func displayName(for source: String) -> String {
        switch source {
        case "claude_code": return "Claude Code"
        case "gemini":      return "Gemini"
        case "odysseus":    return "Odysseus"
        case "hermes":      return "Hermes"
        default:            return source
        }
    }

    // MARK: - Session history

    /// Refresh the history list from disk.
    func refreshSessionHistory() {
        isLoadingHistory = true
        Task {
            do {
                sessionHistory = try await chatService.listSessionsAsync(limit: 50)
            } catch {
                // Fall back to empty — Gateway may be offline
                sessionHistory = []
            }
            isLoadingHistory = false
        }
    }

    /// Switch the chat view to a historical session (read-only).
    func viewHistoricalSession(_ session: CompanionChatService.SessionSummary) {
        viewingHistoricalSessionID = session.id
        Task {
            do {
                historicalMessages = try await chatService.loadSessionMessagesAsync(sessionID: session.id)
            } catch {
                historicalMessages = []
            }
        }
    }

    /// Clear the historical view and start a fresh chat.
    func startNewChat() {
        viewingHistoricalSessionID = nil
        historicalMessages = []
        chatMessages = []
        activeChatSessionID = nil
    }

    // MARK: - Chat mutations (called by CompanionView context menus)

    /// Remove a single message from the live chat by index. No-op when
    /// viewing history (history is read-only).
    func removeChatMessage(at index: Int) {
        guard !isViewingHistory else { return }
        guard chatMessages.indices.contains(index) else { return }
        chatMessages.remove(at: index)
    }

    /// Truncate the live chat at `index` (inclusive), then re-send
    /// the user message at that index. Used by the "Regenerate"
    /// context-menu action.
    func truncateAndResend(at index: Int) {
        guard !isViewingHistory else { return }
        guard chatMessages.indices.contains(index) else { return }
        let target = chatMessages[index]
        guard target.role == .user else { return }
        // Truncate everything from `index` onwards (the user message
        // and any assistant response that followed it).
        chatMessages.removeSubrange(index...)
        // Re-populate input and trigger send
        chatInput = target.content
        sendChat()
    }

    /// Edit a user message's content at the given index, truncate all
    /// subsequent messages, then re-send the edited text. Uses the
    /// existing truncateAndResend mechanism with the modified content.
    func editMessage(at index: Int, newContent: String) {
        guard !isViewingHistory else { return }
        guard chatMessages.indices.contains(index) else { return }
        guard chatMessages[index].role == .user else { return }
        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Update the bubble content in-place
        chatMessages[index].content = trimmed
        // Then truncate and resend from this index
        truncateAndResend(at: index)
    }

    /// Branch the conversation from the message at the given index.
    /// Creates a new Hermes session, copies history up to and including
    /// that message, tags the first message with `parentBranchId`,
    /// and sets the new session as active.
    func branchFromMessage(at index: Int) {
        guard !isViewingHistory else { return }
        guard chatMessages.indices.contains(index) else { return }
        // Keep everything up to and including the selected message
        let branchedMessages = Array(chatMessages[...index])
        // Tag the FIRST message of the new session so the branch
        // marker appears at the top of the conversation
        var tagged = branchedMessages
        if !tagged.isEmpty {
            tagged[0].parentBranchId = tagged[0].id
        }
        // Create a new session (Hermes will allocate a fresh ID on next send)
        activeChatSessionID = nil
        chatMessages = tagged
        chatInput = ""
    }

    // MARK: - Companion helpers

    func switchGateway(_ impl: GatewayImpl) {
        let newGateway = BackendBuilder.gateway(impl)
        chatService.switchProvider(newGateway)
        
        switch impl {
        case .ollama:
            chatService.reconfigure(provider: "ollama", gatewayURL: "http://localhost:11434")
        case .hermes:
            chatService.reconfigure(provider: "hermes", gatewayURL: "http://localhost:8642")
        case .anthropic:
            chatService.reconfigure(provider: "anthropic", gatewayURL: "https://api.anthropic.com")
        case .openai:
            chatService.reconfigure(provider: "openai", gatewayURL: "https://api.openai.com")
        default:
            break
        }
    }

    func loadSelfModel() {
        let path = ARESEnvironment.selfModelFilePath.path
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            selfModelContent = ""
            companionGreeting = "ARES online."
            return
        }
        selfModelContent = content

        // Extract a meaningful greeting from self-model
        if let firstLine = content.components(separatedBy: "\n").first(where: {
            !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("---")
        }) {
            companionGreeting = firstLine.trimmingCharacters(in: .whitespaces)
                .prefix(120).description
        } else {
            companionGreeting = "Good to see you."
        }
    }
}

// MARK: - Tab enum

enum ARESTab: String, CaseIterable, Identifiable {
    case dashboard
    case companion
    case office
    case hub
    case studio
    case automations
    case calendar
    case tasks
    case notes
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard:    return "Dashboard"
        case .companion:    return "Companion"
        case .office:       return "Office"
        case .hub:          return "Hub"
        case .studio:       return "Studio"
        case .automations:  return "Automations"
        case .calendar:     return "Calendar"
        case .tasks:        return "Tasks"
        case .notes:        return "Notes"
        case .settings:     return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:    return "rectangle.grid.2x2.fill"
        case .companion:    return "person.fill.viewfinder"
        case .office:       return "building.2.fill"
        case .hub:          return "square.grid.2x2.fill"
        case .studio:       return "chevron.left.forwardslash.chevron.right"
        case .automations:  return "gearshape.2.fill"
        case .calendar:     return "calendar"
        case .tasks:        return "checklist"
        case .notes:        return "note.text"
        case .settings:     return "gearshape.fill"
        }
    }
}

// MARK: - Voice states

enum VoiceState {
    case idle
    case listening
    case thinking
    case speaking
    case sleeping

    var label: String {
        switch self {
        case .idle:      return "Idle"
        case .listening: return "Listening"
        case .thinking:  return "Thinking"
        case .speaking:  return "Speaking"
        case .sleeping:  return "Sleeping"
        }
    }

    var color: Color {
        switch self {
        case .idle:      return .gray
        case .listening: return .green
        case .thinking:  return .orange
        case .speaking:  return .blue
        case .sleeping:  return .secondary
        }
    }
}

// MARK: - Agent card model

struct AgentCard: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let role: String
    let status: AgentStatus
    let detail: String
}

// MARK: - Chat bubble model

struct ChatBubble: Identifiable, Equatable {
    var id = UUID()
    let role: BubbleRole
    /// Mutable to support streaming token accumulation.
    var content: String
    var timestamp: Date
    /// Source references attached to this message (for inline citations)
    var references: [AttachedReference]? = nil
    /// True while the model is still streaming tokens into this bubble.
    var isStreaming: Bool = false
    /// If set, this bubble is the first message in a branched
    /// conversation that originated from this source message ID.
    var parentBranchId: UUID? = nil
    /// Token count from the gateway response (optional).
    var tokenCount: Int? = nil
    /// Wall-clock latency in seconds for the assistant response.
    var latencySeconds: Double? = nil
    /// Computed cost in USD (v1: always nil, shown as "—").
    var costUSD: Double? = nil
    /// Time when streaming started, used to compute latency.
    var startedAt: Date? = nil

    init(role: BubbleRole, content: String, timestamp: Date = Date(), references: [AttachedReference]? = nil, isStreaming: Bool = false, parentBranchId: UUID? = nil, tokenCount: Int? = nil, latencySeconds: Double? = nil, costUSD: Double? = nil, startedAt: Date? = nil) {
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.references = references
        self.isStreaming = isStreaming
        self.parentBranchId = parentBranchId
        self.tokenCount = tokenCount
        self.latencySeconds = latencySeconds
        self.costUSD = costUSD
        self.startedAt = startedAt
    }
}

enum BubbleRole: Equatable {
    case user
    case assistant
}

enum AgentStatus {
    case active
    case idle
    case offline

    var label: String {
        switch self {
        case .active:  return "Active"
        case .idle:    return "Idle"
        case .offline: return "Offline"
        }
    }

    var color: Color {
        switch self {
        case .active:  return .green
        case .idle:    return .orange
        case .offline: return .gray
        }
    }
}

// MARK: - Attached reference model

/// A source session that the user has attached to a chat message as context.
/// Used for inline citations and prompt preamble building.
struct AttachedReference: Identifiable, Equatable, Codable {
    let id: UUID
    let sessionId: String
    let sourceName: String
    let title: String?
    let timestamp: Date?
    let snippet: String?

    init(
        id: UUID = UUID(),
        sessionId: String,
        sourceName: String,
        title: String? = nil,
        timestamp: Date? = nil,
        snippet: String? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.sourceName = sourceName
        self.title = title
        self.timestamp = timestamp
        self.snippet = snippet
    }
}
