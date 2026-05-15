import Foundation

/// The core abstraction for any AI brain this app connects to.
///
/// Right now we have one adapter: `HermesAdapter` (talks to ARES API at
/// localhost:7860, which forwards to Hermes at :9876). In the future
/// the same protocol can wrap Claude Code, Ollama, any LLM backend.
///
/// The app never talks to localhost directly. It talks to this protocol.
@MainActor
protocol BrainAdapter: AnyObject {
    // ── Connection ──
    var isConnected: Bool { get }
    func connect() async
    func disconnect()

    // ── Conversation ──
    /// Send a user message, get a response as a stream of tokens/events.
    /// The handler is called for each event from the brain.
    func send(message: String) async throws -> AsyncStream<BrainEvent>

    // ── Identity & Personality ──
    func getIdentity() async throws -> BrainIdentity
    func getPersonality() async throws -> BrainPersonality
    func setPersonality(layer: String, trait: String, value: Double) async throws

    // ── Face State ──
    func getFaceState() async throws -> BrainFaceState
    func setFaceState(state: String?) async throws
    func setEmotion(emotion: String) async throws

    // ── Status ──
    func getStatus() async throws -> BrainStatus

    // ── Events (WebSocket push) ──
    /// Subscribe to real-time events pushed by the brain
    var onEvent: ((BrainEvent) -> Void)? { get set }
}

// MARK: - Shared Types

enum BrainEvent {
    case faceState(state: String, emotion: String, intensity: Float, isSpeaking: Bool)
    case chatResponse(text: String)
    case chatStream(token: String)
    case personalityChange(layer: String, trait: String, value: Double)
    case cognitiveSnapshot(CognitiveSnapshot)
    case error(String)
    case connected
    case disconnected
}

struct BrainIdentity: Codable {
    let name: String
    let role: String
    let voice: String
    let selfModel: String
}

struct BrainPersonality: Codable {
    var hexaco: [String: Double]
    var special: [String: Double]
    var expression: [String: Double]
    var domains: [String: Double]
}

struct BrainFaceState: Codable {
    let state: String
    let color: [Double]
    let opacity: Double
    let pulseSpeed: Double
    let pulseAmount: Double
}

struct BrainStatus: Codable {
    let name: String
    let version: String
    let faceState: String
    let uptime: Double
    let websocketClients: Int
}

