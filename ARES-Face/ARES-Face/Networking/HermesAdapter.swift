import Foundation

/// Adapter for the ARES API backend running on localhost:7860.
///
/// This backend wraps Hermes internally — it forwards chat to the Hermes
/// cognition bridge at :9876, so the app talks to the API and the API
/// talks to Hermes. Clean separation: we never touch Hermes's ports directly.
///
/// Protocol: BrainAdapter → HermesAdapter
/// App never knows about WebSocket or REST. It sends messages,
/// receives events, queries personality.
@MainActor
final class HermesAdapter: BrainAdapter {
    // ── BrainAdapter conformance ──

    private(set) var isConnected = false
    var onEvent: ((BrainEvent) -> Void)?

    // ── Internal state ──

    private let wsURL = URL(string: "ws://localhost:7860/ws")!
    private let baseURL = "http://localhost:7860/api"
    private let sessionID = UUID().uuidString
    private var webSocketTask: URLSessionWebSocketTask?
    private var reconnectTimer: Timer?
    /// One active stream per send — holds the continuation that
    /// handleMessage yields tokens into.
    private var currentContinuation: AsyncStream<BrainEvent>.Continuation?

    func connect() async {
        connectWebSocket()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
        isConnected = false
        onEvent?(.disconnected)
        currentContinuation?.finish()
        currentContinuation = nil
    }

    // MARK: - Conversation

    func send(message: String) async throws -> AsyncStream<BrainEvent> {
        return AsyncStream { continuation in
            // Finish any stale continuation from a prior unfinished stream
            self.currentContinuation?.finish()
            self.currentContinuation = continuation

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.currentContinuation = nil
                }
            }

            let clean = message.trimmingCharacters(in: .whitespaces)

            // Send via WebSocket
            let payload: [String: Any] = [
                "type": "chat",
                "text": clean,
                "session_id": sessionID
            ]
            sendWSMessage(payload)
        }
    }

    // MARK: - REST API

    func getIdentity() async throws -> BrainIdentity {
        let data = try await get("/identity")
        let dict = try JSONDecoder().decode([String: String].self, from: data)
        return BrainIdentity(
            name: dict["name"] ?? "ARES",
            role: dict["role"] ?? "",
            voice: dict["voice"] ?? "",
            selfModel: dict["self_model"] ?? ""
        )
    }

    func getPersonality() async throws -> BrainPersonality {
        let data = try await get("/personality")
        return try JSONDecoder().decode(BrainPersonality.self, from: data)
    }

    func setPersonality(layer: String, trait: String, value: Double) async throws {
        let body: [String: Any] = ["layer": layer, "trait": trait, "value": value]
        _ = try await post("/personality", body: body)
    }

    func getFaceState() async throws -> BrainFaceState {
        let data = try await get("/face")
        return try JSONDecoder().decode(BrainFaceState.self, from: data)
    }

    func setFaceState(state: String?) async throws {
        var body: [String: Any] = [:]
        if let state = state { body["state"] = state }
        _ = try await post("/face", body: body)
    }

    func setEmotion(emotion: String) async throws {
        let body: [String: Any] = ["emotion": emotion]
        _ = try await post("/face", body: body)
    }

    func getStatus() async throws -> BrainStatus {
        let data = try await get("/status")
        let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        return BrainStatus(
            name: dict["name"] as? String ?? "ARES",
            version: dict["version"] as? String ?? "",
            faceState: dict["face_state"] as? String ?? "unknown",
            uptime: dict["uptime"] as? Double ?? 0,
            websocketClients: dict["websocket_clients"] as? Int ?? 0
        )
    }

    // MARK: - WebSocket

    private func connectWebSocket() {
        let session = URLSession(configuration: .default)
        var request = URLRequest(url: wsURL)
        request.timeoutInterval = 5

        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        isConnected = true
        onEvent?(.connected)

        // Request initial snapshot
        sendWSMessage(["action": "get_cognitive_snapshot"])
        startReceiving()
    }

    private func startReceiving() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.startReceiving()
                case .failure:
                    self.isConnected = false
                    self.onEvent?(.disconnected)
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let t): text = t
        case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
        @unknown default: return
        }

        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "face_state":
            let state = json["state"] as? String ?? "idle"
            let emotion = json["emotion"] as? String ?? "neutral"
            let intensity = Float(json["intensity"] as? Double ?? 0.2)
            let speaking = state == "speaking"
            onEvent?(.faceState(state: state, emotion: emotion, intensity: intensity, isSpeaking: speaking))

        case "chat_stream":
            // Backend-sent token events — yield immediately
            if let token = json["text"] as? String, let cont = currentContinuation {
                cont.yield(.chatStream(token: token))
            }

        case "chat_response":
            if let text = json["text"] as? String, let cont = currentContinuation {
                // Backend sends full responses. Simulate streaming by
                // yielding 3-5 word chunks inline with small delays.
                Task {
                    let words = text.split(separator: " ")
                    var buffer = ""
                    for (i, word) in words.enumerated() {
                        buffer += (buffer.isEmpty ? "" : " ") + word
                        // Yield every 3-5 words (chunk size varies for natural feel)
                        if (i + 1) % 4 == 0 || i == words.count - 1 {
                            cont.yield(.chatStream(token: buffer))
                            buffer = ""
                            if i < words.count - 1 {
                                try? await Task.sleep(nanoseconds: 30_000_000) // 30ms between chunks
                            }
                        }
                    }
                    // Signal completion — the stream consumer uses this
                    // to transition state back to idle.
                    cont.yield(.chatResponse(text: text))
                    cont.finish()
                    currentContinuation = nil
                }
            }

        case "personality_change":
            if let layer = json["layer"] as? String,
               let trait = json["trait"] as? String,
               let value = json["value"] as? Double {
                onEvent?(.personalityChange(layer: layer, trait: trait, value: value))
            }

        case "cognitive_snapshot":
            if let snapshot = try? JSONDecoder().decode(CognitiveSnapshot.self, from: data) {
                onEvent?(.cognitiveSnapshot(snapshot))
            }

        case "pong":
            break

        default:
            break
        }
    }

    // MARK: - Helpers

    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.connectWebSocket()
            }
        }
    }

    private func get(_ path: String) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return data
    }

    private func post(_ path: String, body: [String: Any]) async throws -> Data {
        guard let url = URL(string: "\(baseURL)\(path)") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        return data
    }

    private func sendWSMessage(_ dict: [String: Any]) {
        guard let json = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: json, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { error in
            if let error = error {
                print("[HermesAdapter] WS send error: \(error.localizedDescription)")
            }
        }
    }
}