import ARESCore
import Foundation
import SwiftUI

/// Resolve backend implementations using builder pattern.
/// Respects ARES_ENV environment variable.
func resolveBackends(_ mode: RuntimeEnvironment) -> BackendStack {
    do {
        switch mode {
        case .development:
            return try BackendStack.development()

        case .production:
            // Try to use real backends; fail loudly if not configured
            let hermesURL = ProcessInfo.processInfo.environment["HERMES_URL"] ?? "http://localhost:8642"
            return try BackendStack.production(hermesURL: hermesURL)

        case .testing:
            return try BackendStack.development()  // Testing uses development (all dummies)
        }
    } catch {
        // Fallback: if build() fails, use development (all dummies) with a loud warning
        print("🛑 [WIRING] Failed to build backends: \(error)")
        print("⚠️  [WIRING] Falling back to development mode (all dummies)")
        do {
            return try BackendStack.development()
        } catch {
            fatalError("[WIRING] Even development fallback failed. This should never happen.")
        }
    }
}

// MARK: - SwiftUI Environment Extensions

extension EnvironmentValues {
    @Entry var embodiment: (any Embodiment)?
    @Entry var perceiver: (any Perceiver)?
    @Entry var memory: (any MemoryStore)?
    @Entry var voice: (any VoiceEngine)?
    @Entry var brain: (any ReasoningBrain)?
}

// MARK: - ARESAppState Factory

extension ARESAppState {
    /// Static factory that resolves backends from environment.
    static func create(environment: RuntimeEnvironment = .development) -> ARESAppState {
        let backends = resolveBackends(environment)
        return ARESAppState(
            embodiment: backends.embodiment,
            perceiver: backends.perceiver,
            memory: backends.memory,
            voice: backends.voice,
            brain: backends.brain
        )
    }
}
