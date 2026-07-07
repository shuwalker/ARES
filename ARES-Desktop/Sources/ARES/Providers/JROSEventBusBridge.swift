import Foundation
import Network
import ARESCore

/// JROSEventBusBridge connects ARES to the JROS Python Backend via Unix Domain Sockets.
/// It wraps a LocalEventBus and proxies events to/from JROS.
public final class JROSEventBusBridge: EventBus, @unchecked Sendable {
    public var capabilities: Set<String> { ["subscribe", "publish", "history", "uds_bridge"] }
    
    private let localBus = LocalEventBus()
    private let queue = DispatchQueue(label: "com.ares.jros.bridge")
    private var connection: NWConnection?
    
    public init(socketPath: String = "/tmp/ares_jros.sock") {
        let endpoint = NWEndpoint.unix(path: socketPath)
        let parameters = NWParameters.tcp
        let conn = NWConnection(to: endpoint, using: parameters)
        self.connection = conn
        
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("✅ [JROS Bridge] Connected to JROS at \(socketPath)")
                self?.receiveLoop()
            case .failed(let error):
                print("⚠️ [JROS Bridge] Connection failed: \(error)")
                // Reconnect logic could go here
            case .cancelled:
                print("⚠️ [JROS Bridge] Connection cancelled.")
            default:
                break
            }
        }
        
        conn.start(queue: queue)
        
        // We proxy ReasoningEvent directly in the publish() override.
    }
    
    private func receiveLoop() {
        guard let conn = connection else { return }
        
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, context, isComplete, error in
            if let data = content, !data.isEmpty, let self = self {
                // Split by newline
                if let str = String(data: data, encoding: .utf8) {
                    let lines = str.split(separator: "\n")
                    for line in lines {
                        self.handleIncomingJSON(String(line))
                    }
                }
            }
            
            if let err = error {
                print("⚠️ [JROS Bridge] Receive error: \(err)")
                return
            }
            
            if !isComplete {
                self?.receiveLoop()
            }
        }
    }
    
    private func handleIncomingJSON(_ jsonString: String) {
        guard let data = jsonString.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = dict["type"] as? String else {
            return
        }
        
        Task {
            if type == "turn_result" {
                let text = dict["text"] as? String ?? ""
                let err = dict["error"] as? String
                let finalResponse = err != nil ? "Error: \(err!)" : text
                
                let event = ReasoningEvent(prompt: "", response: finalResponse, tokensUsed: 0)
                try? await self.localBus.publish(event)
            } else if type == "agent_status" {
                // Map JROS status to something ARES understands, like an EmbodimentEvent or WorldEvent.
                // For now, let's just publish a ReasoningEvent if it's "thinking" to trigger UI
                if let status = dict["status"] as? [String: Any], let state = status["state"] as? String {
                    if state == "thinking" || state == "tool" {
                        let event = EmbodimentEvent(action: "thinking", success: true)
                        try? await self.localBus.publish(event)
                    } else if state == "ready" {
                        let event = EmbodimentEvent(action: "ready", success: true)
                        try? await self.localBus.publish(event)
                    }
                }
            }
        }
    }
    
    private func sendToJROS(type: String, text: String) {
        guard let conn = connection, conn.state == .ready else { return }
        
        let payload: [String: Any] = [
            "type": type,
            "text": text
        ]
        
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              var strData = String(data: data, encoding: .utf8) else { return }
        
        strData += "\n"
        let finalData = strData.data(using: .utf8)!
        
        conn.send(content: finalData, completion: .contentProcessed({ error in
            if let err = error {
                print("⚠️ [JROS Bridge] Send error: \(err)")
            }
        }))
    }
    
    // MARK: - EventBus Protocol
    
    public func subscribe<T: Codable & Sendable>(_ eventType: T.Type) -> AsyncStream<T> {
        return localBus.subscribe(eventType)
    }
    
    public func publish<T: Codable & Sendable>(_ event: T) async throws {
        // Intercept specific events and send to JROS
        if let reason = event as? ReasoningEvent {
            if reason.response.isEmpty { // Meaning it's a request to reason
                sendToJROS(type: "user_prompt", text: reason.prompt)
            }
        }
        
        try await localBus.publish(event)
    }
    
    public func history<T: Codable & Sendable>(_ eventType: T.Type, limit: Int) async throws -> [T] {
        return try await localBus.history(eventType, limit: limit)
    }
}
