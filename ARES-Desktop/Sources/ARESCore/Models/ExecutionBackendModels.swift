import Foundation

/// A backend ARES can use to turn natural human intent into work.
///
/// Hermes and JROS are peer full agentic frameworks. ARES-native services,
/// local model runners, cloud providers, and future runtimes are also valid
/// backends. ARES owns the product experience; backends provide capability.
public enum ExecutionBackendKind: String, Codable, CaseIterable, Hashable, Sendable {
    case hermes
    case jros
    case aresNative = "ares_native"
    case localModel = "local_model"
    case cloudProvider = "cloud_provider"
    case future
}

/// Capabilities ARES routes by. These are product-level capabilities, not
/// provider names and not UI labels.
public enum ExecutionCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case naturalLanguageInterface = "natural_language_interface"
    case uiPresentation = "ui_presentation"
    case automationFlow = "automation_flow"
    case agentTurn = "agent_turn"
    case toolUse = "tool_use"
    case sessionContinuity = "session_continuity"
    case memory
    case scheduling
    case delegation
    case verification
    case modelInference = "model_inference"
    case voiceInput = "voice_input"
    case voiceOutput = "voice_output"
    case vision
    case robotics
    case eventBus = "event_bus"
    case hardwareSafety = "hardware_safety"
}

public enum ExecutionBackendHealthState: String, Codable, Hashable, Sendable {
    case healthy
    case degraded
    case unavailable
}

public struct ExecutionBackendHealth: Codable, Equatable, Sendable {
    public let state: ExecutionBackendHealthState
    public let latencyMs: Double?
    public let checkedAt: Date
    public let message: String?

    public init(
        state: ExecutionBackendHealthState,
        latencyMs: Double? = nil,
        checkedAt: Date = Date(),
        message: String? = nil
    ) {
        self.state = state
        self.latencyMs = latencyMs
        self.checkedAt = checkedAt
        self.message = message
    }

    public var isUsable: Bool {
        state == .healthy || state == .degraded
    }
}

public struct ExecutionBackendDescriptor: Codable, Equatable, Sendable {
    public let kind: ExecutionBackendKind
    public let displayName: String
    public let capabilities: Set<ExecutionCapability>
    public let health: ExecutionBackendHealth
    public let notes: String?

    public init(
        kind: ExecutionBackendKind,
        displayName: String,
        capabilities: Set<ExecutionCapability>,
        health: ExecutionBackendHealth = ExecutionBackendHealth(state: .healthy),
        notes: String? = nil
    ) {
        self.kind = kind
        self.displayName = displayName
        self.capabilities = capabilities
        self.health = health
        self.notes = notes
    }

    public var isUsable: Bool {
        health.isUsable
    }
}

public struct ExecutionBackendRequest: Codable, Equatable, Sendable {
    public let userIntent: String
    public let requiredCapabilities: Set<ExecutionCapability>
    public let allowedBackends: Set<ExecutionBackendKind>?
    public let preferHybrid: Bool

    public init(
        userIntent: String,
        requiredCapabilities: Set<ExecutionCapability>,
        allowedBackends: Set<ExecutionBackendKind>? = nil,
        preferHybrid: Bool = false
    ) {
        self.userIntent = userIntent
        self.requiredCapabilities = requiredCapabilities
        self.allowedBackends = allowedBackends
        self.preferHybrid = preferHybrid
    }
}

public enum ExecutionBackendRouteMode: Codable, Equatable, Sendable {
    case single(ExecutionBackendKind)
    case hybrid([ExecutionBackendKind])
    case unavailable
}

public struct ExecutionBackendRoute: Codable, Equatable, Sendable {
    public let mode: ExecutionBackendRouteMode
    public let selectedBackends: [ExecutionBackendKind]
    public let satisfiedCapabilities: Set<ExecutionCapability>
    public let missingCapabilities: Set<ExecutionCapability>
    public let rationale: [String]

    public init(
        mode: ExecutionBackendRouteMode,
        selectedBackends: [ExecutionBackendKind],
        satisfiedCapabilities: Set<ExecutionCapability>,
        missingCapabilities: Set<ExecutionCapability>,
        rationale: [String]
    ) {
        self.mode = mode
        self.selectedBackends = selectedBackends
        self.satisfiedCapabilities = satisfiedCapabilities
        self.missingCapabilities = missingCapabilities
        self.rationale = rationale
    }

    public var isRoutable: Bool {
        missingCapabilities.isEmpty && !selectedBackends.isEmpty
    }
}

public struct ExecutionRequest: Codable, Sendable {
    public let id: String
    public let userIntent: String
    public let context: ConversationContext
    public let requiredCapabilities: Set<ExecutionCapability>

    public init(
        id: String = UUID().uuidString,
        userIntent: String,
        context: ConversationContext = ConversationContext(),
        requiredCapabilities: Set<ExecutionCapability>
    ) {
        self.id = id
        self.userIntent = userIntent
        self.context = context
        self.requiredCapabilities = requiredCapabilities
    }
}

public struct ExecutionResult: Codable, Equatable, Sendable {
    public let requestId: String
    public let backend: ExecutionBackendKind
    public let text: String
    public let evidence: [String]
    public let metadata: [String: AnyCodable]

    public init(
        requestId: String,
        backend: ExecutionBackendKind,
        text: String,
        evidence: [String] = [],
        metadata: [String: AnyCodable] = [:]
    ) {
        self.requestId = requestId
        self.backend = backend
        self.text = text
        self.evidence = evidence
        self.metadata = metadata
    }
}
