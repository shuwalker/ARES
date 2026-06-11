import Foundation

/// No-op PersonaProvider for testing. Returns default ARES persona.
public final class DummyPersonaProvider: PersonaProvider, @unchecked Sendable {
    public let identifier = "dummy_persona"
    public let displayName = "ARES (Default)"

    public init() {}

    public func getTraits() async throws -> PersonalityTraits {
        PersonalityTraits()
    }

    public func updateTraits(_ updates: [String: AnyCodable]) async throws {
        print("🤖 [DUMMY] updateTraits: \(updates.keys)")
    }

    public func getCommunicationStyle() async throws -> CommunicationStyle {
        CommunicationStyle()
    }

    public func getBehavioralPreferences() async throws -> BehavioralPreferences {
        BehavioralPreferences()
    }

    public func getSystemPrompt(context: ConversationContext) async throws -> String {
        "You are ARES, a helpful assistant."
    }

    public func learn(from experience: PersonaLearningExperience) async throws {
        print("🤖 [DUMMY] learn: \(experience.feedback.prefix(40))")
    }

    public func getMetadata() async throws -> PersonaMetadata {
        PersonaMetadata()
    }
}
