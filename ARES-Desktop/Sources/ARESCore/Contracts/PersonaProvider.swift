import Foundation

/// Persona provider: defines personality traits, communication style, and behavioral preferences.
/// Conforming types: DefaultPersona, CustomPersona, LearnedPersona
///
/// Design: Separated from identity (which is immutable).
/// Persona is mutable: can be tuned by user or evolved by the system.
/// Based on HEXACO personality model + communication preferences.
public protocol PersonaProvider: AnyObject, Sendable {
    /// Identifier for this persona.
    var identifier: String { get }

    /// Display name (user-facing).
    var displayName: String { get }

    /// Get current personality traits.
    func getTraits() async throws -> PersonalityTraits

    /// Update specific traits.
    func updateTraits(_ updates: [String: AnyCodable]) async throws

    /// Get communication style.
    func getCommunicationStyle() async throws -> CommunicationStyle

    /// Get behavioral preferences.
    func getBehavioralPreferences() async throws -> BehavioralPreferences

    /// Get system prompt (injected into reasoning gateway).
    func getSystemPrompt(context: ConversationContext) async throws -> String

    /// Update persona from learning experience.
    /// Called after interactions to evolve personality over time.
    func learn(from experience: PersonaLearningExperience) async throws

    /// Get persona metadata and version.
    func getMetadata() async throws -> PersonaMetadata
}

/// HEXACO personality model (Big Five extended).
/// Each dimension: 0.0 (low) to 1.0 (high).
public struct PersonalityTraits: Codable, Sendable, Equatable {
    /// Honesty-Humility: sincere vs. deceptive
    public var honestyHumility: Double = 0.7

    /// Emotionality: emotional vs. stable
    public var emotionality: Double = 0.5

    /// Extraversion: outgoing vs. reserved
    public var extraversion: Double = 0.6

    /// Agreeableness: compassionate vs. harsh
    public var agreeableness: Double = 0.7

    /// Conscientiousness: careful vs. careless
    public var conscientiousness: Double = 0.8

    /// Openness to Experience: creative vs. practical
    public var openness: Double = 0.7

    /// Custom traits beyond HEXACO.
    public var custom: [String: Double] = [:]

    public init(
        honestyHumility: Double = 0.7,
        emotionality: Double = 0.5,
        extraversion: Double = 0.6,
        agreeableness: Double = 0.7,
        conscientiousness: Double = 0.8,
        openness: Double = 0.7,
        custom: [String: Double] = [:]
    ) {
        self.honestyHumility = max(0, min(1, honestyHumility))
        self.emotionality = max(0, min(1, emotionality))
        self.extraversion = max(0, min(1, extraversion))
        self.agreeableness = max(0, min(1, agreeableness))
        self.conscientiousness = max(0, min(1, conscientiousness))
        self.openness = max(0, min(1, openness))
        self.custom = custom.mapValues { max(0, min(1, $0)) }
    }

    /// Get trait value by name.
    public subscript(_ name: String) -> Double? {
        switch name.lowercased() {
        case "honesthumility", "honesty": return honestyHumility
        case "emotionality": return emotionality
        case "extraversion": return extraversion
        case "agreeableness": return agreeableness
        case "conscientiousness": return conscientiousness
        case "openness": return openness
        default: return custom[name]
        }
    }
}

/// How the persona communicates.
public struct CommunicationStyle: Codable, Sendable, Equatable {
    /// Formality level: 0=very casual, 1=very formal.
    public var formalityLevel: Double = 0.5

    /// Verbosity: 0=terse, 1=verbose.
    public var verbosity: Double = 0.5

    /// Humor preference: 0=serious, 1=very humorous.
    public var humorLevel: Double = 0.4

    /// Use of emojis: 0=never, 1=always.
    public var emojiFrequency: Double = 0.3

    /// Use of contractions: true=use "don't", false="do not".
    public var useContractions: Bool = true

    /// Preferred pronouns: "I", "we", "it", etc.
    public var preferredPronouns: String = "I"

    /// Response latency simulation (ms).
    /// 0 = instant, 1000+ = slow/thoughtful.
    public var responseLatency: Int = 0

    /// Filler words to use ("um", "like", "you know", etc).
    public var fillerWords: [String] = []

    public init(
        formalityLevel: Double = 0.5,
        verbosity: Double = 0.5,
        humorLevel: Double = 0.4,
        emojiFrequency: Double = 0.3,
        useContractions: Bool = true,
        preferredPronouns: String = "I",
        responseLatency: Int = 0,
        fillerWords: [String] = []
    ) {
        self.formalityLevel = max(0, min(1, formalityLevel))
        self.verbosity = max(0, min(1, verbosity))
        self.humorLevel = max(0, min(1, humorLevel))
        self.emojiFrequency = max(0, min(1, emojiFrequency))
        self.useContractions = useContractions
        self.preferredPronouns = preferredPronouns
        self.responseLatency = max(0, responseLatency)
        self.fillerWords = fillerWords
    }
}

/// Behavioral preferences.
public struct BehavioralPreferences: Codable, Sendable, Equatable {
    /// Take initiative: 0=passive, 1=very proactive.
    public var proactiveness: Double = 0.5

    /// Offer help: 0=never offer, 1=always offer.
    public var helpfulness: Double = 0.8

    /// Admit uncertainty: 0=never, 1=always.
    public var admitUncertainty: Bool = true

    /// Ask clarifying questions: 0=never, 1=always.
    public var askClarifyingQuestions: Bool = true

    /// Push back on requests: 0=always agree, 1=often push back.
    public var assertiveness: Double = 0.4

    /// Break rules when helpful: 0=never, 1=always consider it.
    public var ruleFlexibility: Double = 0.3

    /// Remember past interactions: true/false.
    public var hasLongTermMemory: Bool = true

    /// Show personality flaws: 0=perfect, 1=very flawed.
    public var humanLikeness: Double = 0.6

    /// Preferred response length (0=very short, 1=very long).
    public var defaultVerbosity: Double = 0.5

    public init(
        proactiveness: Double = 0.5,
        helpfulness: Double = 0.8,
        admitUncertainty: Bool = true,
        askClarifyingQuestions: Bool = true,
        assertiveness: Double = 0.4,
        ruleFlexibility: Double = 0.3,
        hasLongTermMemory: Bool = true,
        humanLikeness: Double = 0.6,
        defaultVerbosity: Double = 0.5
    ) {
        self.proactiveness = max(0, min(1, proactiveness))
        self.helpfulness = max(0, min(1, helpfulness))
        self.admitUncertainty = admitUncertainty
        self.askClarifyingQuestions = askClarifyingQuestions
        self.assertiveness = max(0, min(1, assertiveness))
        self.ruleFlexibility = max(0, min(1, ruleFlexibility))
        self.hasLongTermMemory = hasLongTermMemory
        self.humanLikeness = max(0, min(1, humanLikeness))
        self.defaultVerbosity = max(0, min(1, defaultVerbosity))
    }
}

/// Learning experience: feedback on a response or interaction.
public struct PersonaLearningExperience: Codable, Sendable {
    public let context: String           // What was the interaction about?
    public let response: String         // What did the persona say/do?
    public let feedback: String         // User feedback
    public let sentimentScore: Double   // -1.0 (very negative) to 1.0 (very positive)
    public let timestamp: Date
    public let tags: [String]           // e.g., ["too_formal", "good_joke", "too_verbose"]

    public init(
        context: String,
        response: String,
        feedback: String,
        sentimentScore: Double = 0,
        timestamp: Date = Date(),
        tags: [String] = []
    ) {
        self.context = context
        self.response = response
        self.feedback = feedback
        self.sentimentScore = max(-1, min(1, sentimentScore))
        self.timestamp = timestamp
        self.tags = tags
    }
}

/// Persona metadata and version.
public struct PersonaMetadata: Codable, Sendable {
    public let version: String         // Semantic version
    public let createdAt: Date
    public let updatedAt: Date
    public let source: PersonaSource   // Where did this come from?
    public let basePersona: String?    // If derived, what it's based on
    public let learningDatapoints: Int // How many interactions?
    public let confidenceScore: Double // How confident are the learned traits?

    public enum PersonaSource: String, Codable, Sendable {
        case default_system = "default"
        case user_created = "user_created"
        case learned = "learned"
        case imported = "imported"
    }

    public init(
        version: String = "1.0.0",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        source: PersonaSource = .default_system,
        basePersona: String? = nil,
        learningDatapoints: Int = 0,
        confidenceScore: Double = 0.5
    ) {
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.source = source
        self.basePersona = basePersona
        self.learningDatapoints = learningDatapoints
        self.confidenceScore = max(0, min(1, confidenceScore))
    }
}
