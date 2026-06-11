import Foundation
import ARESCore

final class LocalEventBus: EventBus, @unchecked Sendable {
    var capabilities: Set<String> { ["subscribe", "publish", "history", "local"] }
    
    private let center = NotificationCenter.default
    private let historyQueue = DispatchQueue(label: "com.ares.eventbus.history")
    private var eventHistory: [String: [Any]] = [:]
    
    // MARK: - EventBus Protocol
    
    func subscribe<T: Codable & Sendable>(_ eventType: T.Type) -> AsyncStream<T> {
        let name = notificationName(for: eventType)
        
        return AsyncStream { continuation in
            let task = Task {
                for await notification in center.publisher(for: name).values {
                    if let payload = notification.userInfo?["payload"] as? T {
                        continuation.yield(payload)
                    }
                }
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
    
    func publish<T: Codable & Sendable>(_ event: T) async throws {
        let name = notificationName(for: T.self)
        
        // Record in history
        historyQueue.sync {
            var arr = eventHistory[name.rawValue] ?? []
            arr.append(event)
            // keep last 100
            if arr.count > 100 { arr.removeFirst() }
            eventHistory[name.rawValue] = arr
        }
        
        center.post(name: name, object: nil, userInfo: ["payload": event])
    }
    
    func history<T: Codable & Sendable>(_ eventType: T.Type, limit: Int) async throws -> [T] {
        let name = notificationName(for: eventType)
        
        return historyQueue.sync {
            let arr = eventHistory[name.rawValue] as? [T] ?? []
            return Array(arr.suffix(limit))
        }
    }
    
    private func notificationName<T>(for type: T.Type) -> Notification.Name {
        return Notification.Name("ARES.EventBus.\(String(describing: type))")
    }
}
