import Foundation
import SwiftUI
import ARESCore

// MARK: - App State

@MainActor
final class ARESAppState: ObservableObject {
    // MARK: - Bootstrap state
    @Published var hasBootstrapped: Bool {
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

    // MARK: - Chat state
    @Published var chatMessages: [ChatBubble] = []
    @Published var chatInput: String = ""
    @Published var isChatProcessing: Bool = false
    @Published var activeChatSessionID: String? = nil
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

    private let scanner = DependencyScanner()
    private let installer = DependencyInstaller()
    private let chatService = CompanionChatService.shared
    private var refreshTimer: Timer?

    init() {
        self.hasBootstrapped = UserDefaults.standard.bool(forKey: "ARES.hasBootstrapped")
        refreshLiveStats()
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

        // Build the prompt — prepend a small reference preamble so the
        // model has the source title + timestamp + snippet, then the user's text.
        let prompt = Self.buildPromptWithReferences(text: text, references: refs)

        // Append user bubble with references attached (so the UI can render chips)
        let userBubble = ChatBubble(role: .user, content: text, references: refs.isEmpty ? nil : refs)
        chatMessages.append(userBubble)
        chatInput = ""
        attachedReferences = []
        isChatProcessing = true
        voiceState = .thinking

        // Use existing session ID for continuity, or start a new one
        let sessionID = activeChatSessionID

        Task {
            do {
                let result = try await chatService.sendMessage(
                    prompt,
                    sessionID: sessionID,
                    model: companionConfig.model,
                    provider: companionConfig.provider
                )
                await MainActor.run {
                    let assistantBubble = ChatBubble(
                        role: .assistant,
                        content: result.responseText,
                        references: refs.isEmpty ? nil : refs
                    )
                    chatMessages.append(assistantBubble)
                    activeChatSessionID = result.sessionID
                    isChatProcessing = false
                    voiceState = .idle

                    // Persist session with the just-appended messages
                    let firstUserMsg = chatMessages.first(where: { $0.role == .user })?.content ?? text
                    let title = String(firstUserMsg.prefix(64))
                    let now = Date()
                    let toPersist: [PersistedChatMessage] = [
                        PersistedChatMessage(
                            role: .user,
                            content: text,
                            timestamp: now,
                            references: refs.isEmpty ? nil : refs
                        ),
                        PersistedChatMessage(
                            role: .assistant,
                            content: result.responseText,
                            timestamp: now,
                            references: nil
                        )
                    ]
                    chatService.persistSession(
                        id: result.sessionID,
                        title: title,
                        messages: toPersist
                    )
                    refreshSessionHistory()
                }
            } catch {
                await MainActor.run {
                    chatMessages.append(ChatBubble(
                        role: .assistant,
                        content: "ARES backend error: \(error.localizedDescription)"
                    ))
                    isChatProcessing = false
                    voiceState = .idle
                }
            }
        }
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
        sessionHistory = chatService.listSessions(limit: 50)
        isLoadingHistory = false
    }

    /// Switch the chat view to a historical session (read-only).
    func viewHistoricalSession(_ session: CompanionChatService.SessionSummary) {
        viewingHistoricalSessionID = session.id
        if let messages = chatService.loadSessionMessages(sessionID: session.id) {
            historicalMessages = messages
        } else {
            historicalMessages = []
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

    // MARK: - Companion helpers

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
    case companion
    case office
    case hub
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .companion: return "Companion"
        case .office:    return "Office"
        case .hub:       return "Hub"
        case .settings:  return "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .companion: return "person.fill.viewfinder"
        case .office:    return "building.2.fill"
        case .hub:       return "square.grid.2x2.fill"
        case .settings:  return "gearshape.fill"
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
    let id = UUID()
    let role: BubbleRole
    let content: String
    let timestamp: Date = Date()
    /// Source references attached to this message (for inline citations)
    var references: [AttachedReference]? = nil
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
