import Foundation

/// Private learned model of the owner. Public code may define this schema;
/// real owner data must live in runtime storage, not in the repository.
public struct OwnerModel: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var communication: OwnerCommunicationPreferences
    public var decisions: OwnerDecisionPreferences
    public var acceptedPatterns: [OwnerPattern]
    public var rejectedPatterns: [OwnerPattern]
    public var projectStandards: [OwnerStandard]
    public var corrections: [OwnerCorrection]
    public var confidence: Double

    public init(
        schemaVersion: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        communication: OwnerCommunicationPreferences = OwnerCommunicationPreferences(),
        decisions: OwnerDecisionPreferences = OwnerDecisionPreferences(),
        acceptedPatterns: [OwnerPattern] = [],
        rejectedPatterns: [OwnerPattern] = [],
        projectStandards: [OwnerStandard] = [],
        corrections: [OwnerCorrection] = [],
        confidence: Double = 0.0
    ) {
        self.schemaVersion = schemaVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.communication = communication
        self.decisions = decisions
        self.acceptedPatterns = acceptedPatterns
        self.rejectedPatterns = rejectedPatterns
        self.projectStandards = projectStandards
        self.corrections = corrections
        self.confidence = max(0, min(1, confidence))
    }
}

public struct OwnerCommunicationPreferences: Codable, Sendable, Equatable {
    public var preferredDirectness: Double
    public var preferredDetail: Double
    public var prefersEvidenceFirst: Bool
    public var bannedPhrases: [String]

    public init(
        preferredDirectness: Double = 0.7,
        preferredDetail: Double = 0.5,
        prefersEvidenceFirst: Bool = true,
        bannedPhrases: [String] = []
    ) {
        self.preferredDirectness = max(0, min(1, preferredDirectness))
        self.preferredDetail = max(0, min(1, preferredDetail))
        self.prefersEvidenceFirst = prefersEvidenceFirst
        self.bannedPhrases = bannedPhrases
    }
}

public struct OwnerDecisionPreferences: Codable, Sendable, Equatable {
    public var defaultAutonomy: OwnerAutonomyLevel
    public var prefersWorkingArtifacts: Bool
    public var prefersPrivateByDefault: Bool
    public var askBeforeDestructiveActions: Bool

    public init(
        defaultAutonomy: OwnerAutonomyLevel = .executeAndVerify,
        prefersWorkingArtifacts: Bool = true,
        prefersPrivateByDefault: Bool = true,
        askBeforeDestructiveActions: Bool = true
    ) {
        self.defaultAutonomy = defaultAutonomy
        self.prefersWorkingArtifacts = prefersWorkingArtifacts
        self.prefersPrivateByDefault = prefersPrivateByDefault
        self.askBeforeDestructiveActions = askBeforeDestructiveActions
    }
}

public enum OwnerAutonomyLevel: String, Codable, Sendable, Equatable {
    case askFirst
    case planThenExecute
    case executeAndVerify
}

public struct OwnerPattern: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var summary: String
    public var evidence: String?
    public var confidence: Double
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        summary: String,
        evidence: String? = nil,
        confidence: Double = 0.5,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.summary = summary
        self.evidence = evidence
        self.confidence = max(0, min(1, confidence))
        self.updatedAt = updatedAt
    }
}

public struct OwnerStandard: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var area: String
    public var rule: String
    public var evidence: String?
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        area: String,
        rule: String,
        evidence: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.area = area
        self.rule = rule
        self.evidence = evidence
        self.updatedAt = updatedAt
    }
}

public struct OwnerPreference: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var key: String
    public var value: String
    public var evidence: String?
    public var confidence: Double
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        key: String,
        value: String,
        evidence: String? = nil,
        confidence: Double = 0.5,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.key = key
        self.value = value
        self.evidence = evidence
        self.confidence = max(0, min(1, confidence))
        self.updatedAt = updatedAt
    }
}

public struct OwnerCorrection: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var originalBehavior: String
    public var correctedBehavior: String
    public var evidence: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        originalBehavior: String,
        correctedBehavior: String,
        evidence: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.originalBehavior = originalBehavior
        self.correctedBehavior = correctedBehavior
        self.evidence = evidence
        self.createdAt = createdAt
    }
}

public struct OwnerModelContext: Codable, Sendable, Equatable {
    public var request: String
    public var communication: OwnerCommunicationPreferences
    public var decisions: OwnerDecisionPreferences
    public var activeStandards: [OwnerStandard]
    public var relevantAcceptedPatterns: [OwnerPattern]
    public var relevantRejectedPatterns: [OwnerPattern]
    public var recentCorrections: [OwnerCorrection]
    public var confidence: Double

    public init(
        request: String,
        communication: OwnerCommunicationPreferences,
        decisions: OwnerDecisionPreferences,
        activeStandards: [OwnerStandard],
        relevantAcceptedPatterns: [OwnerPattern],
        relevantRejectedPatterns: [OwnerPattern],
        recentCorrections: [OwnerCorrection],
        confidence: Double
    ) {
        self.request = request
        self.communication = communication
        self.decisions = decisions
        self.activeStandards = activeStandards
        self.relevantAcceptedPatterns = relevantAcceptedPatterns
        self.relevantRejectedPatterns = relevantRejectedPatterns
        self.recentCorrections = recentCorrections
        self.confidence = max(0, min(1, confidence))
    }
}
