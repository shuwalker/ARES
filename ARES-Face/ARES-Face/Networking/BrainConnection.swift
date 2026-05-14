import Foundation
import Combine

@MainActor
class BrainConnection: ObservableObject {
    @Published var agentState: AgentState = .idle
    @Published var avatarExpression: AvatarExpression = .neutral
    @Published var messages: [ARESMessage] = []
    @Published var inputText = ""
    @Published var backendConnected = false
    @Published var immersionLevel: ImmersionLevel = .light
    @Published var intensity: Float = 0.2
    @Published var isSpeaking: Bool = false
    @Published var cognitive: CognitiveSnapshot = .idle
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let sessionID = UUID().uuidString
    private var reconnectTimer: Timer?
    private let wsURL = URL(string: "ws://localhost:7860/ws")!
    private let baseURL = "http://localhost:7860/api"
    
    // MARK: - Connection
    
    func connect() {
        connectWebSocket()
        checkHealth()
    }
    
    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }
    
    // MARK: - WebSocket
    
    private func connectWebSocket() {
        let session = URLSession(configuration: .default)
        var request = URLRequest(url: wsURL)
        request.timeoutInterval = 5
        
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()

        // Start receiving messages
        receiveMessage()

        // Request an initial cognitive snapshot so the heartbeat panel
        // populates immediately, before the first phase transition fires.
        sendWSMessage(["action": "get_cognitive_snapshot"])
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                
                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.receiveMessage()  // Continue receiving
                case .failure(let error):
                    print("WebSocket receive error: \(error.localizedDescription)")
                    self.backendConnected = false
                    self.scheduleReconnect()
                }
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseMessage(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseMessage(text)
            }
        @unknown default:
            break
        }
    }
    
    private func parseMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }
        
        switch type {
        case "face_state":
            if let state = json["state"] as? String {
                agentState = AgentState(rawValue: state) ?? .idle
            }
            if let emotion = json["emotion"] as? String {
                avatarExpression = AvatarExpression(rawValue: emotion) ?? .neutral
            }
            if let newIntensity = json["intensity"] as? Double {
                intensity = Float(newIntensity)
            }
            // Update config-based intensity
            let config = FaceConfig.config(for: agentState)
            if intensity == 0 { intensity = config.intensity }
            isSpeaking = agentState == .speaking
            
        case "chat_response":
            if let responseText = json["text"] as? String {
                messages.append(ARESMessage(text: responseText, isUser: false))
            }
            
        case "personality_update":
            // Handle personality updates if needed
            break
            
        case "pong":
            break

        case "cognitive_snapshot":
            if let snapshot = try? JSONDecoder().decode(CognitiveSnapshot.self, from: data) {
                cognitive = snapshot
            }

        default:
            break
        }
    }
    
    private func sendWSMessage(_ dict: [String: Any]) {
        guard let json = try? JSONSerialization.data(withJSONObject: dict),
              let text = String(data: json, encoding: .utf8) else { return }
        webSocketTask?.send(.string(text)) { error in
            if let error = error {
                print("WebSocket send error: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Reconnection
    
    private func scheduleReconnect() {
        reconnectTimer?.invalidate()
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.connectWebSocket()
            }
        }
    }
    
    // MARK: - REST API
    
    func checkHealth() {
        guard let url = URL(string: "\(baseURL)/status") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] _, response, _ in
            Task { @MainActor in
                self?.backendConnected = (response as? HTTPURLResponse)?.statusCode == 200
            }
        }.resume()
    }
    
    // MARK: - Public Methods
    
    func sendMessage(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let clean = text.trimmingCharacters(in: .whitespaces)
        messages.append(ARESMessage(text: clean, isUser: true))
        inputText = ""
        agentState = .thinking
        avatarExpression = .thinking
        intensity = FaceConfig.config(for: .thinking).intensity
        
        // Try WebSocket first
        if webSocketTask != nil {
            sendWSMessage([
                "type": "chat",
                "text": clean,
                "session_id": sessionID
            ])
        } else {
            // Fallback to REST
            sendRESTChat(clean)
        }
    }
    
    private func sendRESTChat(_ text: String) {
        guard let url = URL(string: "\(baseURL)/chat") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["text": text, "session_id": sessionID]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
        request.httpBody = data
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self else { return }
                if let error = error {
                    print("REST chat error: \(error.localizedDescription)")
                    // Provide graceful fallback
                    self.messages.append(ARESMessage(
                        text: "I'm currently offline. My deeper reasoning loop is still coming online.",
                        isUser: false
                    ))
                    self.agentState = .idle
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return
                }
                
                if let responseText = json["response"] as? String {
                    self.messages.append(ARESMessage(text: responseText, isUser: false))
                }
                if let state = json["state"] as? String {
                    self.agentState = AgentState(rawValue: state) ?? .idle
                }
                if let expression = json["expression"] as? String {
                    self.avatarExpression = AvatarExpression(rawValue: expression) ?? .neutral
                }
                self.intensity = FaceConfig.config(for: self.agentState).intensity
                self.backendConnected = true
            }
        }.resume()
    }
    
    func cycleImmersion() {
        let all = ImmersionLevel.allCases
        let idx = all.firstIndex(of: immersionLevel)!
        immersionLevel = all[(idx + 1) % all.count]
    }
}