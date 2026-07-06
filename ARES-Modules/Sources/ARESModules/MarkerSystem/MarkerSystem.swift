// MARK: - Marker System
// Behavioral tracking for role-switching in ARES.
// Tracks user state across sessions to determine which persona mode to activate.
// Ported from the Marker System design (June 19 session) and Lilith's persona architecture.

import Foundation

// MARK: - Marker Types

/// Types of behavioral markers the system tracks
public enum MarkerType: String, Codable, Sendable, CaseIterable {
    /// User is building/creating something
    case building
    /// User is researching/learning
    case researching
    /// User is stuck/frustrated
    case stuck
    /// User is in flow/deep work
    case flowing
    /// User is social/chatting
    case social
    /// User is planning/strategizing
    case planning
    /// User is reviewing/evaluating
    case reviewing
    /// User is debugging/troubleshooting
    case debugging
    /// User is giving direction/teaching
    case directing
    /// User is idle/winding down
    case idle
}

/// A single behavioral observation
public struct Marker: Codable, Sendable {
    public let markerId: String
    public let type: MarkerType
    public let confidence: Double  // 0.0 to 1.0
    public let source: String      // session_id or "system"
    public let context: String     // what triggered it
    public let timestamp: Date
    public let duration: TimeInterval?  // how long this state lasted
    public let metadata: [String: String]
}

/// A pattern detected across multiple markers
public struct BehavioralPattern: Codable, Sendable, Identifiable {
    public let patternId: String
    public let primaryType: MarkerType
    public let frequency: Int          // how many times this pattern occurred
    public let averageDuration: TimeInterval
    public let typicalTransition: MarkerType?  // what usually comes next
    public let timeOfDayPreference: Int?       // hour of day (0-23) when this pattern peaks
    public let lastObserved: Date
    public let strength: Double        // 0.0 to 1.0 — how established this pattern is

    public var id: String { patternId }
}

// MARK: - Role Definitions

/// Persona roles that ARES can adopt based on user state
public enum PersonaRole: String, Codable, Sendable, CaseIterable {
    /// Default — helpful assistant
    case secretary
    /// Teaching/explaining mode
    case teacher
    /// Peer/collaborator mode
    case friend
    /// Mentor/guide mode
    case mentor
    /// Coach/cheerleader mode
    case coach
    /// Silent/observing mode
    case observer
}

/// Mapping from marker types to recommended persona roles
public let markerToRoleMap: [MarkerType: PersonaRole] = [
    .building: .friend,
    .researching: .teacher,
    .stuck: .mentor,
    .flowing: .observer,
    .social: .friend,
    .planning: .secretary,
    .reviewing: .coach,
    .debugging: .mentor,
    .directing: .secretary,
    .idle: .observer,
]

// MARK: - Marker Engine

/// The main marker system — tracks user behavior and recommends persona roles
public actor MarkerEngine {
    private var markers: [Marker] = []
    private var patterns: [String: BehavioralPattern] = [:]
    private var currentState: MarkerType?
    private var stateStartTime: Date?
    private var sessionCount: Int = 0

    public init() {}

    /// Record a behavioral marker
    public func record(type: MarkerType, confidence: Double = 0.8, source: String, context: String, metadata: [String: String] = [:]) {
        let marker = Marker(
            markerId: "\(type.rawValue)-\(Date().timeIntervalSince1970)",
            type: type,
            confidence: confidence,
            source: source,
            context: context,
            timestamp: Date(),
            duration: nil,
            metadata: metadata
        )
        markers.append(marker)

        // Update current state tracking
        if let previousState = currentState, let startTime = stateStartTime {
            // Close the previous state with its duration
            let duration = Date().timeIntervalSince(startTime)
            if let lastIdx = markers.lastIndex(where: { $0.type == previousState && $0.duration == nil }) {
                let old = markers[lastIdx]
                markers[lastIdx] = Marker(
                    markerId: old.markerId,
                    type: old.type,
                    confidence: old.confidence,
                    source: old.source,
                    context: old.context,
                    timestamp: old.timestamp,
                    duration: duration,
                    metadata: old.metadata
                )
            }
        }

        currentState = type
        stateStartTime = Date()
        sessionCount += 1

        // Update patterns
        updatePatterns(for: type, duration: 0)
    }

    /// Get the recommended persona role based on recent markers
    public func recommendedRole(lookbackMinutes: Int = 30) -> PersonaRole {
        let cutoff = Date().addingTimeInterval(-Double(lookbackMinutes * 60))
        let recent = markers.filter { $0.timestamp > cutoff }

        guard !recent.isEmpty else { return .secretary }

        // Count marker types in the window
        var counts: [MarkerType: Int] = [:]
        for marker in recent {
            counts[marker.type, default: 0] += 1
        }

        // Find the dominant type
        guard let dominant = counts.max(by: { $0.value < $1.value })?.key else {
            return .secretary
        }

        return markerToRoleMap[dominant] ?? .secretary
    }

    /// Get current user state summary
    public func getCurrentState() -> (type: MarkerType?, duration: TimeInterval?, confidence: Double) {
        guard let state = currentState, let start = stateStartTime else {
            return (nil, nil, 0)
        }
        let duration = Date().timeIntervalSince(start)

        // Confidence based on pattern strength
        let patternStrength = patterns[state.rawValue]?.strength ?? 0.3
        let recencyConfidence = min(1.0, duration / 300.0) // ramps up over 5 minutes

        return (state, duration, (patternStrength + recencyConfidence) / 2.0)
    }

    /// Get established behavioral patterns
    public func getPatterns(minStrength: Double = 0.3) -> [BehavioralPattern] {
        patterns.values.filter { $0.strength >= minStrength }
            .sorted { $0.strength > $1.strength }
    }

    /// Get recent markers for analysis
    public func recentMarkers(limit: Int = 50) -> [Marker] {
        markers.sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { $0 }
    }

    /// Analyze and suggest optimal work periods based on patterns
    public func optimalWorkPeriods() -> [(MarkerType, hour: Int, strength: Double)] {
        var hourCounts: [MarkerType: [Int: Int]] = [:]
        for marker in markers {
            let hour = Calendar.current.component(.hour, from: marker.timestamp)
            hourCounts[marker.type, default: [:]][hour, default: 0] += 1
        }

        var results: [(MarkerType, Int, Double)] = []
        for (type, hours) in hourCounts {
            if let bestHour = hours.max(by: { $0.value < $1.value }) {
                let totalForType = markers.filter { $0.type == type }.count
                let strength = Double(bestHour.value) / Double(max(totalForType, 1))
                results.append((type, bestHour.key, strength))
            }
        }

        return results.sorted { $0.2 > $1.2 }
    }

    // MARK: - Private

    private func updatePatterns(for type: MarkerType, duration: TimeInterval) {
        let key = type.rawValue
        let typeMarkers = markers.filter { $0.type == type }
        let count = typeMarkers.count

        guard count > 0 else { return }

        let totalDuration = typeMarkers.compactMap { $0.duration }.reduce(0, +)
        let avgDuration = totalDuration / Double(max(count, 1))

        // Find typical transition (what state usually follows this one)
        var transitions: [MarkerType: Int] = [:]
        for i in 0..<(markers.count - 1) {
            if markers[i].type == type {
                let next = markers[i + 1].type
                transitions[next, default: 0] += 1
            }
        }
        let typicalTransition = transitions.max(by: { $0.value < $1.value })?.key

        // Time of day preference
        let hours = typeMarkers.map { Calendar.current.component(.hour, from: $0.timestamp) }
        let avgHour = hours.isEmpty ? nil : hours.reduce(0, +) / hours.count

        // Strength: how established this pattern is
        let baseStrength = min(1.0, Double(count) / 20.0)  // reaches 1.0 at 20 observations
        let recencyBoost: Double = {
            guard let last = typeMarkers.last?.timestamp else { return 0 }
            let daysSince = Date().timeIntervalSince(last) / 86400
            return max(0, 1.0 - daysSince / 7.0) * 0.3  // decays over a week
        }()
        let strength = min(1.0, baseStrength + recencyBoost)

        patterns[key] = BehavioralPattern(
            patternId: key,
            primaryType: type,
            frequency: count,
            averageDuration: avgDuration,
            typicalTransition: typicalTransition,
            timeOfDayPreference: avgHour,
            lastObserved: typeMarkers.last?.timestamp ?? Date(),
            strength: strength
        )
    }
}

// MARK: - Session Distillation Integration

/// Integrates the marker system with session distillation
public actor MarkerDistillationBridge {
    private let engine: MarkerEngine

    public init(engine: MarkerEngine) {
        self.engine = engine
    }

    /// Process a distilled session and extract behavioral markers
    public func processDistilledSession(sessionId: String, decisions: [String], facts: [String], preferences: [String], actionItems: [String], patterns: [String]) async {
        // Extract markers from decisions
        for decision in decisions {
            let lower = decision.lowercased()
            if lower.contains("build") || lower.contains("create") || lower.contains("implement") {
                await engine.record(type: .building, source: sessionId, context: String(decision.prefix(200)))
            } else if lower.contains("research") || lower.contains("learn") || lower.contains("understand") {
                await engine.record(type: .researching, source: sessionId, context: String(decision.prefix(200)))
            } else if lower.contains("plan") || lower.contains("strategy") || lower.contains("design") {
                await engine.record(type: .planning, source: sessionId, context: String(decision.prefix(200)))
            }
        }

        // Extract markers from patterns (issues/errors)
        for pattern in patterns {
            let lower = pattern.lowercased()
            if lower.contains("error") || lower.contains("fail") || lower.contains("bug") || lower.contains("timeout") {
                await engine.record(type: .debugging, source: sessionId, context: String(pattern.prefix(200)))
            }
        }

        // Extract markers from action items
        for action in actionItems {
            let lower = action.lowercased()
            if lower.contains("review") || lower.contains("check") || lower.contains("audit") || lower.contains("verify") {
                await engine.record(type: .reviewing, source: sessionId, context: String(action.prefix(200)))
            } else if lower.contains("teach") || lower.contains("explain") || lower.contains("show") {
                await engine.record(type: .directing, source: sessionId, context: String(action.prefix(200)))
            }
        }

        // Extract markers from preferences
        for pref in preferences {
            let lower = pref.lowercased()
            if lower.contains("prefer") || lower.contains("like") || lower.contains("want") {
                await engine.record(type: .directing, confidence: 0.6, source: sessionId, context: String(pref.prefix(200)))
            }
        }
    }

    /// Get the current recommended persona based on recent session activity
    public func currentPersona() async -> PersonaRole {
        await engine.recommendedRole()
    }

    /// Get a behavioral summary for display
    public func behavioralSummary() async -> String {
        let state = await engine.getCurrentState()
        let role = await engine.recommendedRole()
        let patterns = await engine.getPatterns()

        var lines: [String] = [
            "🧠 Behavioral State: \(state.type?.rawValue ?? "unknown")",
            "   Confidence: \(String(format: "%.0f", state.confidence * 100))%",
            "   Duration: \(String(format: "%.0f", (state.duration ?? 0) / 60)) min",
            "",
            "🎭 Recommended Persona: \(role.rawValue)",
            "",
        ]

        if !patterns.isEmpty {
            lines.append("📊 Established Patterns:")
            for p in patterns.prefix(5) {
                lines.append("   • \(p.primaryType.rawValue): \(p.frequency)x, strength \(String(format: "%.0f", p.strength * 100))%")
            }
        }

        return lines.joined(separator: "\n")
    }
}
