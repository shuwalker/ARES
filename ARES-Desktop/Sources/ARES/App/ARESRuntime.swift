import ARESCore
import Foundation

@MainActor
enum ARESRuntime {
    static let appState: ARESAppState = {
        // Register tool providers. These flow to tool-capable gateways through
        // ToolRouter/ToolRegistry; execution is gated by ApprovalBroker.
        ToolRegistry.shared.register(provider: N8NToolProvider())
        ToolRegistry.shared.register(provider: NativeComputerControlToolProvider())

        let state = ARESAppState.create(environment: environmentFromLaunchArgs())
        startDummyWarningTimer(environment: environmentFromLaunchArgs())
        return state
    }()

    private static func startDummyWarningTimer(environment: RuntimeEnvironment) {
        guard environment == .production else { return }

        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in
                let usingDummies = [
                    ARESRuntime.appState.embodiment is DummyEmbodiment,
                    ARESRuntime.appState.perceiver is DummyPerceiver,
                    ARESRuntime.appState.memory is DummyMemoryStore,
                    ARESRuntime.appState.voice is DummyVoiceEngine,
                    ARESRuntime.appState.brain is DummyReasoningBrain,
                    ARESRuntime.appState.identity is DummyIdentity,
                    ARESRuntime.appState.mimicry is DummyMimicry,
                    ARESRuntime.appState.world is DummyWorldModel,
                    ARESRuntime.appState.eventBus is DummyEventBus,
                    ARESRuntime.appState.workflow is DummyWorkflow,
                    ARESRuntime.appState.scheduler is DummyScheduler
                ].contains(true)

                if usingDummies {
                    print("⚠️  [ARES] WARNING: Production mode (ARES_ENV=production) but using dummy backends. Configure real services.")
                }
            }
        }
    }
}
