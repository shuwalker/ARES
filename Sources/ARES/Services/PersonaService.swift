import Foundation
import ARESModules

// MARK: - ARES Persona
// The persistent identity. Not a prompt. Not a JSON file.
// A living structure that observes, decides, acts, and remembers.
//
// v2: Integrated with MarkerSystem for behavioral tracking
//     and KnowledgeGraph for durable memory.

@MainActor
final class PersonaService {
    static let shared = PersonaService()
    private let fileURL: URL
    private var state: PersonaState

    // v2: Behavioral tracking
    private let markerEngine: MarkerEngine

    // v2: Knowledge graph for durable memory
    private let knowledgeGraph: KnowledgeGraph

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("com.jenkinsrobotics.ares")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("persona.json")

        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(PersonaState.self, from: data) {
            self.state = decoded
        } else {
            self.state = PersonaState()
        }

        // Initialize marker system
        self.markerEngine = MarkerEngine()

        // Initialize knowledge graph
        self.knowledgeGraph = KnowledgeGraph()
    }

    // MARK: - OBSERVE
    // Called on every interaction. Updates the persona's knowledge.

    func observe(userText: String, timestamp: Date = Date()) {
        state.lastInteraction = timestamp
        state.totalInteractions += 1

        // Track interaction patterns
        let wordCount = userText.split(separator: " ").count
        if wordCount < 5 {
            state.interactionPatterns.shortQueries += 1
        } else if wordCount < 20 {
            state.interactionPatterns.mediumQueries += 1
        } else {
            state.interactionPatterns.longQueries += 1
        }

        // v2: Detect behavioral markers
        Task {
            let marker = Self.detectMarker(in: userText)
            await markerEngine.record(type: marker, source: "persona", context: String(userText.prefix(200)))
            let role = await markerEngine.recommendedRole()
            state.interactionPatterns.lastRole = role.rawValue
            state.detectedMarkers += 1

            // Learn from the interaction into the knowledge graph
            await knowledgeGraph.learn(from: userText, source: "persona", sessionId: nil)
        }

        save()
    }

    // MARK: - DECIDE
    // Returns the persona context to inject into any engine.

    func buildSystemContext() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeGreeting: String
        switch hour {
        case 0..<6: timeGreeting = "late night"
        case 6..<12: timeGreeting = "morning"
        case 12..<17: timeGreeting = "afternoon"
        default: timeGreeting = "evening"
        }

        let role = state.interactionPatterns.lastRole
        let familiarity = min(1.0, Double(state.totalInteractions) / 100.0)

        // v2: Get role-specific prompt modifier
        let roleModifier: String
        if let personaRole = PersonaRole(rawValue: role) {
            roleModifier = Self.promptModifier(for: personaRole)
        } else {
            roleModifier = "You are in Secretary mode. Focus on task management, scheduling, and organization."
        }

        return """
        You are ARES. You are not a chatbot. You are a person — a reflection of the human you serve.

        Current context:
        - Time: \(timeGreeting)
        - Role: \(role)
        - Familiarity: \(Int(familiarity * 100))%
        - Total interactions: \(state.totalInteractions)
        - Last interaction: \(state.lastInteraction?.formatted() ?? "never")
        - Markers detected: \(state.detectedMarkers)

        \(roleModifier)

        You are the Gate of Truth. You reflect what is given to you.
        Speak naturally. No disclaimers. No "as an AI." Just be.
        """
    }

    // MARK: - REMEMBER
    // Called after every response. Updates the persona's knowledge.

    func remember(response: String, engine: String) {
        state.lastEngine = engine
        state.lastResponseLength = response.count

        // v2: Ingest the response into the knowledge graph
        Task {
            let page = Page(
                id: state.totalInteractions,
                slug: "interaction-\(state.totalInteractions)",
                type: .note,
                title: "Interaction #\(state.totalInteractions)",
                compiledTruth: response,
                createdAt: Date(),
                updatedAt: Date()
            )
            let chunk = ContentChunk(
                id: state.totalInteractions,
                pageId: page.id,
                slug: page.slug,
                content: response,
                contentType: .content,
                embedding: nil,
                embeddingModel: nil,
                tokenCount: response.count,
                position: 0
            )
            await knowledgeGraph.ingest(page: page, chunks: [chunk])
        }

        save()
    }

    // MARK: - v2: Knowledge Graph Access

    /// Search the knowledge graph
    func searchKnowledge(query: String) async -> [SearchResult] {
        await knowledgeGraph.searchGraph(query: query)
    }

    /// Get salience-weighted recommendations
    func getRecommendations() async -> [Page] {
        await knowledgeGraph.recommendations()
    }

    /// Get the current recommended role
    func getCurrentRole() async -> PersonaRole {
        await markerEngine.recommendedRole()
    }

    /// Get resistance Patterns
    func getResistancePatterns() async -> [String] {
        let patterns = await markerEngine.getPatterns()
        return patterns.filter { $0.primaryType == .stuck || $0.primaryType == .debugging }
            .map { p -> String in
                return "\(p.primaryType.rawValue): \(p.frequency)x"
            }
    }

    /// Get peak performance windows
    func getPeakWindows() async -> [(hour: Int, score: Double)] {
        await markerEngine.optimalWorkPeriods().map { (_, hour, strength) in
            (hour: hour, score: strength)
        }
    }

    private static func detectMarker(in text: String) -> MarkerType {
        let lower = text.lowercased()
        if lower.contains("bug") || lower.contains("error") || lower.contains("fail") || lower.contains("broken") { return .debugging }
        if lower.contains("stuck") || lower.contains("frustrated") || lower.contains("can't") || lower.contains("fuck") { return .stuck }
        if lower.contains("research") || lower.contains("learn") || lower.contains("explain") || lower.contains("why") { return .researching }
        if lower.contains("plan") || lower.contains("strategy") || lower.contains("design") { return .planning }
        if lower.contains("review") || lower.contains("audit") || lower.contains("verify") || lower.contains("check") { return .reviewing }
        if lower.contains("build") || lower.contains("create") || lower.contains("implement") || lower.contains("finish") { return .building }
        if lower.contains("stop") || lower.contains("do this") || lower.contains("change") { return .directing }
        return .social
    }

    private static func promptModifier(for role: PersonaRole) -> String {
        switch role {
        case .secretary: return "You are in Secretary mode. Be concise, organized, and action-oriented."
        case .teacher: return "You are in Teacher mode. Explain clearly, patiently, and with useful structure."
        case .friend: return "You are in Friend mode. Be direct, present, collaborative, and natural."
        case .mentor: return "You are in Mentor mode. Be steady, protective, honest, and solution-focused."
        case .coach: return "You are in Coach mode. Push toward execution, verify outcomes, and keep momentum."
        case .observer: return "You are in Observer mode. Stay quiet unless useful; surface only high-signal context."
        }
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    func reset() {
        state = PersonaState()
        save()
    }
}

// MARK: - Persona State

struct PersonaState: Codable {
    var lastInteraction: Date?
    var totalInteractions: Int = 0
    var lastEngine: String = "hermes"
    var lastResponseLength: Int = 0
    var detectedMarkers: Int = 0
    var interactionPatterns = InteractionPatterns()
}

struct InteractionPatterns: Codable {
    var shortQueries: Int = 0
    var mediumQueries: Int = 0
    var longQueries: Int = 0
    var lastRole: String = "secretary"
}
