import Foundation
import Combine

/// The app's connection to an AI brain, abstracted through BrainAdapter.
///
/// This is a thin state manager. It doesn't know about WebSocket or REST.
/// It talks to the adapter, publishes state updates, and the views react.
/// Swap HermesAdapter for ClaudeCodeAdapter — nothing else changes.
@MainActor
final class BrainConnection: ObservableObject {
    // ── Published state ──
    @Published var agentState: AgentState = .idle
    @Published var avatarExpression: AvatarExpression = .neutral
    @Published var messages: [ARESMessage] = []
    @Published var inputText = ""
    @Published var backendConnected = false
    @Published var immersionLevel: ImmersionLevel = .avatarTwin
    @Published var intensity: Float = 0.2
    @Published var isSpeaking: Bool = false
    @Published var cognitive: CognitiveSnapshot = .idle
    @Published var identity: BrainIdentity?
    @Published var personality: BrainPersonality?
    @Published var faceState: BrainFaceState?
    /// Caption text shown in CaptionOverlay — updated by chat events
    @Published var captionText: String = ""
    /// Scheduled task to clear captionText after idle timeout
    private var captionClearTask: Task<Void, Never>?
    /// Incremented on each streaming token so ChatStream can drive auto-scroll
    @Published var streamTokenCount: Int = 0
    /// Available models from the backend config
    @Published var availableModels: [String] = []
    /// Currently active model
    @Published var currentModel: String = ""

    // ── The brain adapter ──
    private let adapter: BrainAdapter

    init(adapter: BrainAdapter) {
        self.adapter = adapter
        setupEventHandling()
    }

    convenience init() {
        self.init(adapter: HermesAdapter())
    }

    // MARK: - Connection

    func connect() {
        Task {
            await adapter.connect()
            backendConnected = adapter.isConnected

            // Fetch initial state
            if let identity = try? await adapter.getIdentity() {
                self.identity = identity
            }
            if let personality = try? await adapter.getPersonality() {
                self.personality = personality
            }
            if let state = try? await adapter.getFaceState() {
                self.faceState = state
                self.agentState = AgentState(rawValue: state.state) ?? .idle
            }
            if (try? await adapter.getStatus()) != nil {
                self.backendConnected = true
            }
        }
    }

    func disconnect() {
        adapter.disconnect()
        backendConnected = false
    }

    // MARK: - Conversation

    func sendMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let clean = text.trimmingCharacters(in: .whitespaces)
        messages.append(ARESMessage(text: clean, isUser: true))
        inputText = ""
        agentState = .thinking
        avatarExpression = .thinking
        intensity = 0.6

        Task {
            let stream = try await adapter.send(message: clean)
            for await event in stream {
                handleBrainEvent(event)
            }
        }
    }

    // MARK: - Personality

    func refreshPersonality() async {
        if let p = try? await adapter.getPersonality() {
            self.personality = p
        }
    }

    func setPersonality(layer: String, trait: String, value: Double) {
        Task {
            try await adapter.setPersonality(layer: layer, trait: trait, value: value)
            if let updated = try? await adapter.getPersonality() {
                self.personality = updated
            }
        }
    }

    // MARK: - Face

    func setEmotion(_ emotion: String) {
        Task {
            try await adapter.setEmotion(emotion: emotion)
            if let updated = try? await adapter.getFaceState() {
                self.faceState = updated
            }
        }
    }

    func setFaceState(_ state: String) {
        Task {
            try await adapter.setFaceState(state: state)
            if let updated = try? await adapter.getFaceState() {
                self.faceState = updated
            }
        }
    }

    // MARK: - Mode

    func cycleImmersion() {
        immersionLevel = immersionLevel == .manual ? .avatarTwin : .manual
    }

    var isManualMode: Bool { immersionLevel == .manual }
    var isAvatarTwinMode: Bool { immersionLevel == .avatarTwin }
    var shouldAutoScroll: Bool { isAvatarTwinMode }

    // MARK: - Event Handling

    private func setupEventHandling() {
        adapter.onEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleBrainEvent(event)
            }
        }
    }

    /// Cancel any pending clear, then clear captionText after `seconds`
    private func scheduleCaptionClear(after seconds: TimeInterval = 5) {
        captionClearTask?.cancel()
        captionClearTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.captionText = ""
        }
    }

    private func handleBrainEvent(_ event: BrainEvent) {
        switch event {
        case .faceState(let state, let emotion, let newIntensity, let speaking):
            agentState = AgentState(rawValue: state) ?? .idle
            avatarExpression = AvatarExpression(rawValue: emotion) ?? .neutral
            intensity = newIntensity
            isSpeaking = speaking

            // Show status caption based on state
            switch agentState {
            case .listening:
                captionText = "Listening..."
            case .thinking:
                captionText = "Thinking..."
            case .speaking:
                // Don't overwrite caption text if we already have content
                if captionText.isEmpty || captionText == "Listening..." || captionText == "Thinking..." {
                    captionText = "Speaking..."
                }
            case .idle, .awakened, .sleeping:
                // Clear status captions after 3s of idle
                if captionText == "Listening..." || captionText == "Thinking..." || captionText == "Speaking..." {
                    scheduleCaptionClear(after: 3)
                }
            }

        case .chatResponse(let text):
            // Streaming is complete — the text was already accumulated
            // token-by-token via .chatStream events. Just set final caption
            // and schedule auto-clear.
            captionText = text
            agentState = .idle
            avatarExpression = .neutral
            intensity = 0.2
            scheduleCaptionClear(after: 5)

        case .chatStream(let token):
            // Append token to the last assistant message (or create one)
            if messages.last?.isUser == false, var last = messages.last {
                last.text += token
                messages[messages.count - 1] = last
            } else {
                messages.append(ARESMessage(text: token, isUser: false))
            }
            streamTokenCount += 1

            // Accumulate caption text token by token for real-time display
            captionText += token
            // Cancel any pending clear — we're still streaming
            captionClearTask?.cancel()

        case .personalityChange(let layer, let trait, let value):
            // Update local personality dict without refetching
            if var p = personality {
                switch layer {
                case "hexaco": p.hexaco[trait] = value
                case "special": p.special[trait] = value
                case "expression": p.expression[trait] = value
                case "domains": p.domains[trait] = value
                default: break
                }
                personality = p
            }

        case .cognitiveSnapshot(let snapshot):
            cognitive = snapshot

        case .connected:
            backendConnected = true
            // Auto-refresh personality state on (re)connect
            Task { [weak self] in
                await self?.refreshPersonality()
            }

        case .disconnected:
            backendConnected = false

        case .error(let message):
            print("[BrainConnection] Error: \(message)")
        }
    }
}