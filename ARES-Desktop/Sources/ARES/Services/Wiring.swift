import ARESCore
import Foundation
import os
import SwiftUI

private let wiringLog = Logger(subsystem: "com.ares", category: "Wiring")

extension Notification.Name {
    /// Posted when backend wiring fails and ARES starts in safe (all-dummy) mode.
    static let aresWiringFailed = Notification.Name("ARESWiringFailed")
}

/// UserDefaults key set when wiring falls back to safe mode. Read by the UI to show an alert.
let aresWiringFailedDefaultsKey = "ARES.wiringFailed"

/// Records that wiring fell back to safe mode and signals the UI to surface an alert.
private func signalWiringFailure() {
    UserDefaults.standard.set(true, forKey: aresWiringFailedDefaultsKey)
    NotificationCenter.default.post(name: .aresWiringFailed, object: nil)
}

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
        wiringLog.error("Failed to build backends: \(error.localizedDescription, privacy: .public). Falling back to development mode (all dummies).")
        do {
            return try BackendStack.development()
        } catch {
            // Last resort: construct an all-dummy stack inline (non-throwing) rather than crash.
            wiringLog.fault("Even development fallback failed: \(error.localizedDescription, privacy: .public). Using inline dummy stack.")
            signalWiringFailure()
            return BackendStack(
                embodiment: DummyEmbodiment(),
                perceiver: DummyPerceiver(),
                memory: DummyMemoryStore(),
                voice: DummyVoiceEngine(),
                brain: DummyReasoningBrain(),
                identity: DummyIdentity(),
                mimicry: DummyMimicry(),
                world: DummyWorldModel(),
                eventBus: DummyEventBus(),
                workflow: DummyWorkflow(),
                scheduler: DummyScheduler(),
                environment: .development
            )
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
    @Entry var identity: (any Identity)?
    @Entry var mimicry: (any Mimicry)?
    @Entry var world: (any WorldPerception)?
    @Entry var eventBus: (any EventBus)?
    @Entry var workflow: (any Workflow)?
    @Entry var scheduler: (any Scheduler)?
}

// MARK: - ARESAppState Factory

extension ARESAppState {
    /// Static factory that resolves backends from environment.
    static func create(environment: RuntimeEnvironment = .development) -> ARESAppState {
        let backends = resolveBackends(environment)
        return ARESAppState(stack: backends)
    }
}
