import Foundation

// Mirror of `ares/models/cognitive.py`. Unknown fields are ignored on
// decode, so adding new keys server-side is non-breaking. Bump
// `expectedSchemaVersion` when the contract breaks.

struct CognitiveSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let timestamp: Double
    let running: Bool
    let loop: LoopBlock
    let thought: ThoughtBlock?
    let memoryRecall: [MemoryHitBlock]
    let errors: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case memoryRecall = "memory_recall"
        case timestamp, running, loop, thought, errors
    }

    init(
        schemaVersion: Int,
        timestamp: Double,
        running: Bool,
        loop: LoopBlock,
        thought: ThoughtBlock?,
        memoryRecall: [MemoryHitBlock] = [],
        errors: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.timestamp = timestamp
        self.running = running
        self.loop = loop
        self.thought = thought
        self.memoryRecall = memoryRecall
        self.errors = errors
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        timestamp = try c.decode(Double.self, forKey: .timestamp)
        running = try c.decode(Bool.self, forKey: .running)
        loop = try c.decode(LoopBlock.self, forKey: .loop)
        thought = try c.decodeIfPresent(ThoughtBlock.self, forKey: .thought)
        memoryRecall = (try? c.decode([MemoryHitBlock].self, forKey: .memoryRecall)) ?? []
        errors = try c.decode([String].self, forKey: .errors)
    }

    static let expectedSchemaVersion = 1

    static let idle = CognitiveSnapshot(
        schemaVersion: expectedSchemaVersion,
        timestamp: 0,
        running: false,
        loop: LoopBlock.idle,
        thought: nil,
        memoryRecall: [],
        errors: []
    )
}

struct MemoryHitBlock: Codable, Equatable, Identifiable {
    let id: String
    let score: Double
    let text: String
    let kind: String
}

struct LoopBlock: Codable, Equatable {
    let cycle: Int
    let phase: String
    let urgency: String
    let budgetRemaining: Double
    let tokensUsed: Int
    let elapsedMs: Int

    enum CodingKeys: String, CodingKey {
        case cycle, phase, urgency
        case budgetRemaining = "budget_remaining"
        case tokensUsed = "tokens_used"
        case elapsedMs = "elapsed_ms"
    }

    static let idle = LoopBlock(
        cycle: 0,
        phase: "idle",
        urgency: "low",
        budgetRemaining: 1.0,
        tokensUsed: 0,
        elapsedMs: 0
    )
}

struct ThoughtBlock: Codable, Equatable {
    let summary: String?
    let depth: Int
    let confidence: Double?
    let sentiment: Double?
}
