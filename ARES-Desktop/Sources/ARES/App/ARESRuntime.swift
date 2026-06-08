import ARESCore
import Foundation

@MainActor
enum ARESRuntime {
    static let appState: ARESAppState = {
        let state = ARESAppState.create(environment: environmentFromLaunchArgs())
        startDummyWarningTimer(environment: environmentFromLaunchArgs())
        return state
    }()

    private static func startDummyWarningTimer(environment: RuntimeEnvironment) {
        guard environment == .production else { return }

        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            // Warn if production but using dummies
            let usingDummies = [
                ARESRuntime.appState.embodiment is DummyEmbodiment,
                ARESRuntime.appState.perceiver is DummyPerceiver,
                ARESRuntime.appState.memory is DummyMemoryStore,
                ARESRuntime.appState.voice is DummyVoiceEngine,
                ARESRuntime.appState.brain is DummyReasoningBrain
            ].contains(true)

            if usingDummies {
                print("⚠️  [ARES] WARNING: Production mode (ARES_ENV=production) but using dummy backends. Configure real services.")
            }
        }
    }
}
