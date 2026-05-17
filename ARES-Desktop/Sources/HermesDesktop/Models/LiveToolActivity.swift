import Foundation
import Combine

/// A single tool call event received from the Hermes gateway in real-time.
struct LiveToolEvent: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let context: String?
    let status: LiveToolEventStatus
    let timestamp: Date

    enum LiveToolEventStatus: Equatable, Sendable {
        case started
        case progress(String?)
        case completed
    }
}

/// Observable model that connects to the Hermes gateway WebSocket and streams
/// tool events (tool.start, tool.progress, tool.complete) in real-time.
/// Used by LiveToolActivityView to show what the agent is doing.
@MainActor
final class LiveToolActivityModel: ObservableObject {
    @Published var events: [LiveToolEvent] = []
    @Published var isActive = false
    @Published var connectionError: String?

    private var webSocketTask: URLSessionWebSocketTask?
    private var reconnectTimer: Timer?
    private let maxEvents = 50  // Keep the list from growing forever

    // Gateway config — read from ConnectionStore / AppState
    var gatewayHost: String = "localhost"
    var gatewayPort: Int = 9119
    var sessionToken: String?

    func connect() {
        guard !isActive else { return }

        let token = sessionToken ?? ""
        let wsURLStr = "ws://\(gatewayHost):\(gatewayPort)/api/ws?token=\(token)"
        guard let wsURL = URL(string: wsURLStr) else {
            connectionError = "Invalid WebSocket URL"
            return
        }

        let request = URLRequest(url: wsURL)
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: request)
        self.webSocketTask = task
        task.resume()

        isActive = true
        connectionError = nil
        receiveMessages()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        isActive = false
        reconnectTimer?.invalidate()
        reconnectTimer = nil
    }

    func clear() {
        events.removeAll()
    }

    // MARK: - Private

    private func receiveMessages() {
        guard let task = webSocketTask else { return }

        task.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    if self.isActive {
                        self.receiveMessages()
                    }
                case .failure(let error):
                    self.handleDisconnect(error: error)
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let text):
            parseAndProcessEvent(text)
        case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
                parseAndProcessEvent(text)
            }
        @unknown default:
            break
        }
    }

    private func parseAndProcessEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["method"] as? String == "event",
              let params = json["params"] as? [String: Any],
              let eventType = params["type"] as? String else {
            return
        }

        let payload = params["payload"] as? [String: Any] ?? [:]

        switch eventType {
        case "tool.start":
            handleToolStart(payload)
        case "tool.progress":
            handleToolProgress(payload)
        case "tool.complete":
            handleToolComplete(payload)
        case "tool.generating":
            // Treat generating as progress with a label
            handleToolGenerating(payload)
        case "gateway.ready":
            // Connection confirmed, nothing to display
            break
        default:
            break
        }
    }

    private func handleToolStart(_ payload: [String: Any]) {
        let toolID = payload["tool_id"] as? String ?? UUID().uuidString
        let name = payload["name"] as? String ?? "unknown"
        let context = payload["context"] as? String

        let event = LiveToolEvent(
            id: toolID,
            name: name,
            context: context,
            status: .started,
            timestamp: Date()
        )
        appendEvent(event)
    }

    private func handleToolProgress(_ payload: [String: Any]) {
        let toolID = payload["tool_id"] as? String
        let name = payload["name"] as? String ?? "unknown"
        let preview = payload["preview"] as? String

        if let toolID, let index = events.firstIndex(where: { $0.id == toolID }) {
            // Update existing event
            events[index] = LiveToolEvent(
                id: toolID,
                name: name,
                context: events[index].context,
                status: .progress(preview),
                timestamp: events[index].timestamp
            )
        } else {
            // Orphan progress — create a new entry
            let event = LiveToolEvent(
                id: toolID ?? UUID().uuidString,
                name: name,
                context: preview,
                status: .progress(preview),
                timestamp: Date()
            )
            appendEvent(event)
        }
    }

    private func handleToolComplete(_ payload: [String: Any]) {
        let toolID = payload["tool_id"] as? String
        let name = payload["name"] as? String ?? "unknown"

        if let toolID, let index = events.firstIndex(where: { $0.id == toolID }) {
            events[index] = LiveToolEvent(
                id: toolID,
                name: name,
                context: events[index].context,
                status: .completed,
                timestamp: events[index].timestamp
            )
        } else {
            // Orphan complete — create a completed entry
            let event = LiveToolEvent(
                id: toolID ?? UUID().uuidString,
                name: name,
                context: nil,
                status: .completed,
                timestamp: Date()
            )
            appendEvent(event)
        }
    }

    private func handleToolGenerating(_ payload: [String: Any]) {
        let name = payload["name"] as? String ?? "unknown"
        let preview = payload["preview"] as? String ?? "Generating output..."

        // generating is a type of progress
        let event = LiveToolEvent(
            id: UUID().uuidString,
            name: name,
            context: preview,
            status: .progress(preview),
            timestamp: Date()
        )
        appendEvent(event)
    }

    private func appendEvent(_ event: LiveToolEvent) {
        events.append(event)
        // Trim oldest events if over limit
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }
    }

    private func handleDisconnect(error: Error) {
        isActive = false
        connectionError = error.localizedDescription

        // Auto-reconnect after 5 seconds
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.connect()
            }
        }
    }
}