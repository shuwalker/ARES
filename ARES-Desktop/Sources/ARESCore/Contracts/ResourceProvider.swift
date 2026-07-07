import Foundation

/// A compute node in the distributed ARES network.
public struct ComputeNode: Codable, Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String 
    public let address: String 
    public let capabilities: Set<String> // e.g., ["ComfyUI", "Open-Sora", "Ollama"]
    public let vramAvailableMB: Int
    public let status: NodeStatus
    public let lastHeartbeat: Date

    public enum NodeStatus: String, Codable, Sendable {
        case online, busy, offline
    }

    public init(id: UUID = UUID(), name: String, address: String, capabilities: Set<String>, vramAvailableMB: Int, status: NodeStatus, lastHeartbeat: Date = Date()) {
        self.id = id
        self.name = name
        self.address = address
        self.capabilities = capabilities
        self.vramAvailableMB = vramAvailableMB
        self.status = status
        self.lastHeartbeat = lastHeartbeat
    }
}

/// A compute task for a remote node.
public struct ComputeTask: Codable, Sendable, Identifiable {
    public let id: UUID
    public let type: String // e.g., "image_generation", "video_generation"
    public let payload: [String: AnyCodable]
    public let requiredVRAM: Int

    public init(id: UUID = UUID(), type: String, payload: [String: AnyCodable], requiredVRAM: Int) {
        self.id = id
        self.type = type
        self.payload = payload
        self.requiredVRAM = requiredVRAM
    }
}

public struct TaskResult: Codable, Sendable {
    public let taskId: UUID
    public let status: TaskStatus
    public let output: [String: AnyCodable]?
    public let error: String?

    public enum TaskStatus: String, Codable, Sendable {
        case pending, running, completed, failed
    }

    public init(taskId: UUID, status: TaskStatus, output: [String: AnyCodable]? = nil, error: String? = nil) {
        self.taskId = taskId
        self.status = status
        self.output = output
        self.error = error
    }
}

/// Discovers nodes and dispatches compute tasks.
public protocol ResourceProvider: AnyObject, Sendable {
    func discoverNodes() async throws
    func getAvailableNodes() async -> [ComputeNode]
    func dispatch(task: ComputeTask) async throws -> TaskResult
    func observeNodes() -> AsyncStream<[ComputeNode]>
    var capabilities: Set<String> { get }
}
