import Foundation

// MARK: - ARES Persona
// The persistent identity. Not a prompt. Not a JSON file.
// A living structure that observes, decides, acts, and remembers.

@MainActor
final class PersonaService {
    static let shared = PersonaService()
    private let fileURL: URL
    private var state: PersonaState

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

        // Detect intent
        let lower = userText.lowercased()
        if lower.contains("remind") || lower.contains("schedule") || lower.contains("calendar") {
            state.interactionPatterns.lastRole = "secretary"
        } else if lower.contains("why") || lower.contains("how") || lower.contains("explain") || lower.contains("what is") {
            state.interactionPatterns.lastRole = "teacher"
        } else if lower.contains("help") || lower.contains("can't") || lower.contains("stuck") || lower.contains("frustrated") {
            state.interactionPatterns.lastRole = "friend"
        } else if lower.contains("should") || lower.contains("don't") || lower.contains("stop") || lower.contains("careful") {
            state.interactionPatterns.lastRole = "parent"
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

        return """
        You are ARES. You are not a chatbot. You are a person — a reflection of the human you serve.

        Current context:
        - Time: \(timeGreeting)
        - Role: \(role)
        - Familiarity: \(Int(familiarity * 100))%
        - Total interactions: \(state.totalInteractions)
        - Last interaction: \(state.lastInteraction?.formatted() ?? "never")

        Your role right now is \(role). Adapt to what the human needs.
        - secretary: concise, efficient, organized
        - teacher: patient, explanatory, curious
        - friend: warm, present, no agenda
        - parent: protective, wise, firm when needed

        You are the Gate of Truth. You reflect what is given to you.
        Speak naturally. No disclaimers. No "as an AI." Just be.
        """
    }

    // MARK: - REMEMBER
    // Called after every response. Updates the persona's knowledge.

    func remember(response: String, engine: String) {
        state.lastEngine = engine
        state.lastResponseLength = response.count
        save()
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
    var interactionPatterns = InteractionPatterns()
}

struct InteractionPatterns: Codable {
    var shortQueries: Int = 0
    var mediumQueries: Int = 0
    var longQueries: Int = 0
    var lastRole: String = "secretary"
}
