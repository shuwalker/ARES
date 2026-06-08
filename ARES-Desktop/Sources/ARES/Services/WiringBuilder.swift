import ARESCore
import Foundation
import SwiftUI

/// Backend builder: fluent API for injecting real (or dummy) implementations.
/// Usage:
///   let app = BackendBuilder()
///       .embodiment(.desktop)
///       .perceiver(.local)
///       .memory(.sqlite)
///       .voice(.kokoro)
///       .brain(.hermes(url:))
///       .build()
public final class BackendBuilder: @unchecked Sendable {
    private var _embodiment: (any Embodiment)?
    private var _perceiver: (any Perceiver)?
    private var _memory: (any MemoryStore)?
    private var _voice: (any VoiceEngine)?
    private var _brain: (any ReasoningBrain)?
    private var _identity: (any Identity)?
    private var _mimicry: (any Mimicry)?
    private var _world: (any WorldPerception)?
    private var _eventBus: (any EventBus)?
    private var _workflow: (any Workflow)?
    private var _scheduler: (any Scheduler)?

    public init() {}

    // MARK: - Builder Methods

    public func embodiment(_ impl: EmbodimentImpl) -> Self {
        switch impl {
        case .dummy:
            _embodiment = DummyEmbodiment()
        case .desktop:
            // TODO: Real DesktopEmbodiment when available
            _embodiment = DummyEmbodiment()
            print("⚠️  [WIRING] Embodiment: using dummy (real desktop impl not ready)")
        }
        return self
    }

    public func perceiver(_ impl: PerceiverImpl) -> Self {
        switch impl {
        case .dummy:
            _perceiver = DummyPerceiver()
        case .local(let wsURL):
            // TODO: Real PerceptionClient(url: wsURL)
            _perceiver = DummyPerceiver()
            print("⚠️  [WIRING] Perceiver: using dummy (real websocket client not ready for \(wsURL))")
        case .cloud:
            _perceiver = DummyPerceiver()
            print("⚠️  [WIRING] Perceiver: using dummy (cloud perception not ready)")
        }
        return self
    }

    public func memory(_ impl: MemoryImpl) -> Self {
        switch impl {
        case .dummy:
            _memory = DummyMemoryStore()
        case .sqlite(let path):
            // TODO: Real SQLiteMemoryStore(path: path)
            _memory = DummyMemoryStore()
            print("⚠️  [WIRING] Memory: using dummy (SQLite not ready for \(path))")
        case .vectorDB(let url):
            _memory = DummyMemoryStore()
            print("⚠️  [WIRING] Memory: using dummy (vector DB not ready for \(url))")
        }
        return self
    }

    public func voice(_ impl: VoiceImpl) -> Self {
        switch impl {
        case .dummy:
            _voice = DummyVoiceEngine()
        case .kokoro:
            // TODO: Real KokoroVoiceEngine()
            _voice = DummyVoiceEngine()
            print("⚠️  [WIRING] Voice: using dummy (Kokoro not integrated yet)")
        case .system:
            _voice = DummyVoiceEngine()
            print("⚠️  [WIRING] Voice: using dummy (System TTS not ready)")
        }
        return self
    }

    public func brain(_ impl: BrainImpl) -> Self {
        switch impl {
        case .dummy:
            _brain = DummyReasoningBrain()
        case .hermes(let url):
            // TODO: Real HermesAgentBrain(gatewayURL: url)
            _brain = DummyReasoningBrain()
            print("⚠️  [WIRING] Brain: using dummy (Hermes client not integrated for \(url))")
        case .claude(let apiKey):
            _brain = DummyReasoningBrain()
            print("⚠️  [WIRING] Brain: using dummy (Claude client not ready for \(apiKey.prefix(4))...)")
        case .local(let model):
            _brain = DummyReasoningBrain()
            print("⚠️  [WIRING] Brain: using dummy (Local model \(model) not integrated)")
        }
        return self
    }

    public func identity(_ impl: IdentityImpl) -> Self {
        switch impl {
        case .dummy:
            _identity = DummyIdentity()
        case .filesystem(let path):
            // TODO: Real FileSystemIdentity(path: path)
            _identity = DummyIdentity()
            print("⚠️  [WIRING] Identity: using dummy (filesystem not ready for \(path))")
        }
        return self
    }

    public func mimicry(_ impl: MimicryImpl) -> Self {
        switch impl {
        case .dummy:
            _mimicry = DummyMimicry()
        case .realistic:
            _mimicry = DummyMimicry()
            print("⚠️  [WIRING] Mimicry: using dummy (realistic engine not ready)")
        }
        return self
    }

    public func world(_ impl: WorldImpl) -> Self {
        switch impl {
        case .dummy:
            _world = DummyWorldModel()
        case .vision(let modelName):
            _world = DummyWorldModel()
            print("⚠️  [WIRING] World: using dummy (vision model \(modelName) not integrated)")
        }
        return self
    }

    public func eventBus(_ impl: EventBusImpl) -> Self {
        switch impl {
        case .dummy:
            _eventBus = DummyEventBus()
        case .zmq(let endpoint):
            _eventBus = DummyEventBus()
            print("⚠️  [WIRING] EventBus: using dummy (ZMQ not ready for \(endpoint))")
        }
        return self
    }

    public func workflow(_ impl: WorkflowImpl) -> Self {
        switch impl {
        case .dummy:
            _workflow = DummyWorkflow()
        case .filesystem(let path):
            _workflow = DummyWorkflow()
            print("⚠️  [WIRING] Workflow: using dummy (filesystem not ready for \(path))")
        }
        return self
    }

    public func scheduler(_ impl: SchedulerImpl) -> Self {
        switch impl {
        case .dummy:
            _scheduler = DummyScheduler()
        case .launchctl:
            _scheduler = DummyScheduler()
            print("⚠️  [WIRING] Scheduler: using dummy (launchctl not integrated)")
        case .hermes:
            _scheduler = DummyScheduler()
            print("⚠️  [WIRING] Scheduler: using dummy (Hermes scheduler not integrated)")
        }
        return self
    }

    /// Factory for gateway providers (can be called from views/services).
    public static func gateway(_ impl: GatewayImpl) -> any GatewayProvider {
        switch impl {
        case .dummy:
            return DummyGatewayProvider()
        case .ollama(let url):
            return OllamaGatewayProvider(baseURL: URL(string: url) ?? URL(string: "http://localhost:11434")!)
        case .hermes(let url):
            let apiKey = ProcessInfo.processInfo.environment["API_SERVER_KEY"] ?? ""
            return HermesGatewayProvider(baseURL: URL(string: url) ?? URL(string: "http://localhost:8642")!, apiKey: apiKey)
        case .anthropic(let apiKey):
            return DummyGatewayProvider() // TODO: Implement AnthropicGatewayProvider
        case .openai(let apiKey):
            return DummyGatewayProvider() // TODO: Implement OpenAIGatewayProvider
        }
    }

    // MARK: - Build

    public func build(checkProduction: Bool = true) throws -> BackendStack {
        let env = environmentFromLaunchArgs()

        // Safety check: reject production if using dummies
        if checkProduction && env == .production {
            let usingDummies = [
                _embodiment is DummyEmbodiment,
                _perceiver is DummyPerceiver,
                _memory is DummyMemoryStore,
                _voice is DummyVoiceEngine,
                _brain is DummyReasoningBrain
            ].contains(true)

            if usingDummies {
                let msg = "Production mode selected but backends are dummies. Set ARES_ENV=development or configure real backends."
                print("🛑 [WIRING] FATAL: \(msg)")
                throw WiringError.productionWithDummies(msg)
            }
        }

        return BackendStack(
            embodiment: _embodiment ?? DummyEmbodiment(),
            perceiver: _perceiver ?? DummyPerceiver(),
            memory: _memory ?? DummyMemoryStore(),
            voice: _voice ?? DummyVoiceEngine(),
            brain: _brain ?? DummyReasoningBrain(),
            identity: _identity ?? DummyIdentity(),
            mimicry: _mimicry ?? DummyMimicry(),
            world: _world ?? DummyWorldModel(),
            eventBus: _eventBus ?? DummyEventBus(),
            workflow: _workflow ?? DummyWorkflow(),
            scheduler: _scheduler ?? DummyScheduler(),
            environment: env
        )
    }
}

// MARK: - Implementation Enums

public enum EmbodimentImpl {
    case dummy
    case desktop
}

public enum PerceiverImpl {
    case dummy
    case local(wsURL: String)
    case cloud
}

public enum MemoryImpl {
    case dummy
    case sqlite(path: String)
    case vectorDB(url: String)
}

public enum VoiceImpl {
    case dummy
    case kokoro
    case system
}

public enum BrainImpl {
    case dummy
    case hermes(url: String)
    case claude(apiKey: String)
    case local(model: String)
}

public enum IdentityImpl {
    case dummy
    case filesystem(path: String)
}

public enum MimicryImpl {
    case dummy
    case realistic
}

public enum WorldImpl {
    case dummy
    case vision(model: String)
}

public enum EventBusImpl {
    case dummy
    case zmq(endpoint: String)
}

public enum WorkflowImpl {
    case dummy
    case filesystem(path: String)
}

public enum SchedulerImpl {
    case dummy
    case launchctl
    case hermes
}

public enum GatewayImpl {
    case dummy
    case ollama(url: String)
    case hermes(url: String)
    case anthropic(apiKey: String)
    case openai(apiKey: String)
}

// MARK: - Updated BackendStack (Extended)

public struct BackendStack {
    let embodiment: any Embodiment
    let perceiver: any Perceiver
    let memory: any MemoryStore
    let voice: any VoiceEngine
    let brain: any ReasoningBrain
    let identity: any Identity
    let mimicry: any Mimicry
    let world: any WorldPerception
    let eventBus: any EventBus
    let workflow: any Workflow
    let scheduler: any Scheduler
    let environment: RuntimeEnvironment
}

// MARK: - Error Handling

public enum WiringError: Error, Sendable {
    case productionWithDummies(String)
    case missingRequiredBackend(String)
}

// MARK: - Environment Helpers

enum RuntimeEnvironment {
    case development
    case production
    case testing
}

func environmentFromLaunchArgs() -> RuntimeEnvironment {
    let env = ProcessInfo.processInfo.environment["ARES_ENV"] ?? "development"
    switch env.lowercased() {
    case "production", "prod":
        return .production
    case "testing", "test":
        return .testing
    default:
        return .development
    }
}

// MARK: - Convenience Factory

extension BackendStack {
    /// Development preset: all dummies.
    static func development() throws -> BackendStack {
        try BackendBuilder()
            .embodiment(.dummy)
            .perceiver(.dummy)
            .memory(.dummy)
            .voice(.dummy)
            .brain(.dummy)
            .identity(.dummy)
            .mimicry(.dummy)
            .world(.dummy)
            .eventBus(.dummy)
            .workflow(.dummy)
            .scheduler(.dummy)
            .build(checkProduction: false)
    }

    /// Production preset: real backends (will fail if not configured).
    static func production(hermesURL: String = "http://localhost:8642") throws -> BackendStack {
        try BackendBuilder()
            .embodiment(.desktop)
            .perceiver(.local(wsURL: "ws://localhost:9100"))
            .memory(.sqlite(path: "~/.ares/memory.db"))
            .voice(.kokoro)
            .brain(.hermes(url: hermesURL))
            .identity(.filesystem(path: "~/.ares/identity.json"))
            .mimicry(.realistic)
            .world(.vision(model: "yolov8"))
            .eventBus(.zmq(endpoint: "tcp://127.0.0.1:5555"))
            .workflow(.filesystem(path: "~/.ares/workflows"))
            .scheduler(.hermes)
            .build(checkProduction: true)
    }
}
