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
    let errors: [String]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case timestamp, running, loop, thought, errors
    }

    static let expectedSchemaVersion = 1

    static let idle = CognitiveSnapshot(
        schemaVersion: expectedSchemaVersion,
        timestamp: 0,
        running: false,
        loop: LoopBlock.idle,
        thought: nil,
        errors: []
    )
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
