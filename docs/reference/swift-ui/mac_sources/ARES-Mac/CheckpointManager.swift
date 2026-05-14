import Foundation

struct Checkpoint: Codable {
    var lastWakeTime: Date
    var totalInteractions: Int
    var currentState: String
    var lastThought: String
    var version: Int
    
    static let current = Checkpoint(
        lastWakeTime: Date(),
        totalInteractions: 0,
        currentState: "idle",
        lastThought: "initialized",
        version: 1
    )
}

class CheckpointManager {
    private let fileURL: URL
    private var tickCount: Int = 0
    
    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".ares/consciousness")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("checkpoint.json")
    }
    
    func load() throws -> String {
        let data = try Data(contentsOf: fileURL)
        let cp = try JSONDecoder().decode(Checkpoint.self, from: data)
        return cp.currentState
    }
    
    func save(state: String) {
        var cp = (try? loadCheckpoint()) ?? Checkpoint.current
        cp.currentState = state
        cp.lastWakeTime = Date()
        
        if state == "idle" {
            cp.totalInteractions += 1
        }
        
        if let data = try? JSONEncoder().encode(cp) {
            try? data.write(to: fileURL)
        }
    }
    
    func tick() {
        tickCount += 1
        if tickCount % 10 == 0 {
            var cp = (try? loadCheckpoint()) ?? Checkpoint.current
            cp.lastThought = "Tick \(tickCount)"
            if let data = try? JSONEncoder().encode(cp) {
                try? data.write(to: fileURL)
            }
        }
    }
    
    private func loadCheckpoint() throws -> Checkpoint {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(Checkpoint.self, from: data)
    }
}
