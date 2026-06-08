# ARES — Autonomous Reasoning & Execution System

**v0.1.0 — Modular Framework Release**

A standalone native Apple framework for building embodied AI experiences. Modular by design, swappable by default, runs on macOS, iOS, and beyond.

**ARES is not a wrapper. It's a framework.** It ships with its own implementations of every component, but every component is replaceable through clean contracts. Think of it as a lego kit — the pieces snap together through well-defined interfaces, and you can swap any piece for a different one when you need different capabilities.

---

## The Shape

ARES is built as a set of modular concerns. Each concern is a single contract, a single folder, independently buildable, independently testable, independently swappable. The app is the wiring layer — it knows which concrete implementation plugs into which contract, and nothing else.

```
ARES/
├── Sources/
│   ├── ARESCore/           # the framework library
│   │   ├── Contracts/      # one protocol per concern (14 total)
│   │   ├── Dummies/        # safe default implementations (14 total)
│   │   ├── Models/         # shared data types
│   │   └── Services/       # helpers
│   ├── ARES/               # the app shell
│   │   ├── App/            # app entry, state, runtime
│   │   ├── Providers/      # concrete gateway implementations
│   │   ├── Widgets/        # composable ui pieces (5 total)
│   │   ├── Views/          # dashboard and page layouts
│   │   ├── Services/       # service layer + wiring builder
│   │   └── Bootstrap/      # dependency detection
│   └── Tests/              # contract tests
└── docs/                   # architecture and design docs
```

---

## The Concerns

The framework defines protocols for every concern an embodied AI system needs. Each is a single, focused, swappable component.

**Core Reasoning:**
- `GatewayProvider` — talks to an LLM backend. Local or cloud, streaming or not, with or without tools, with or without vision.
- `ReasoningBrain` — planning, reflecting, assembling responses. Consumes the gateway.
- `ToolProvider` — capabilities the AI can invoke. File system, web, code execution, anything.

**Embodiment & Perception:**
- `Embodiment` — the body. Avatar, face, voice, gesture, gaze.
- `Perceiver` — sensory input. Webcam, microphone, screen, events.
- `VoiceEngine` — speech in and out. Transcription, synthesis, prosody.
- `Mimicry` — the layer that makes it feel alive. Delayed mirroring of perception into body output.
- `WorldModel` — live scene graph. What's in the environment, what changed, who's here.

**Memory & Personality:**
- `MemoryStore` — persistent knowledge. Facts, history, episodic memory. Swappable backend.
- `Identity` — immutable "I am ARES" core. Name, role, voice, self-model.
- `PersonaProvider` — mutable traits, communication style, behavioral preferences.

**Coordination:**
- `EventBus` — pub/sub layer that lets components talk without knowing about each other.
- `Workflow` — task tracking (optional).
- `Scheduler` — scheduled background work (optional).

---

## The Contract

Every concern has a contract in `ARESCore/Contracts/`. The contract is the only public surface. Implementations are private. Components talk only through contracts, never concrete classes, never shared files, never inheritance.

Every concern ships with a dummy implementation in `ARESCore/Dummies/`. Dummies are safe defaults that let the app boot without any real backend. Dummies warn loudly if they end up running in production.

The wiring layer in `ARES/Services/WiringBuilder.swift` is the only place that knows which concrete implementation plugs into which contract. Swap a brick by changing one line.

---

## The Rules

1. **One concern per contract.** Don't mix.
2. **Wiring layer owns concretions.** Everywhere else imports the protocol.
3. **Components talk through EventBus, not direct calls.** This prevents the leak.
4. **Dummies warn every 60 seconds if running in production.** Production refuses to build with dummies.
5. **No new top-level folders.** Everything goes under existing structure.
6. **Tests target contracts, not concrete classes.** A test passes with any implementation.

---

## What's Built (Phase 1 + Phase 2)

**14 Protocol Contracts:**
- ✅ Embodiment, Perceiver, MemoryStore, VoiceEngine, ReasoningBrain
- ✅ ToolProvider, GatewayProvider, PersonaProvider
- ✅ Identity, Mimicry, WorldModel, EventBus, Workflow, Scheduler

**14 Dummy Implementations:**
- ✅ One safe default per contract
- ✅ All Sendable (Swift 6 strict concurrency)
- ✅ Production safety: reject dummies or warn every 60s

**Gateway Providers (Phase 2):**
- ✅ OllamaGatewayProvider — local models via localhost:11434
- ✅ HermesGatewayProvider — Hermes agent via localhost:8642
- ✅ Extensible protocol for custom providers

**Modular Widgets (Phase 2):**
- ✅ ChatWidget — standalone chat interface
- ✅ ModelPickerWidget — switch between Ollama/Hermes at runtime
- ✅ PerceptionWidget — camera preview + vision frame capture
- ✅ AvatarWidget — avatar with emotion states
- ✅ HistoryWidget — session history list

**Dashboard (Phase 2):**
- ✅ DashboardView — composable layout system
- ✅ Configurable widget positions (row, column, spans)
- ✅ Persistent layout to `~/.ares/dashboard_layout.json`
- ✅ Edit mode for widget reordering

---

## Key Files

| Path | Purpose |
|------|---------|
| `Package.swift` | SPM manifest |
| `ARES-Desktop/Sources/ARESCore/Contracts/` | 14 protocol contracts |
| `ARES-Desktop/Sources/ARESCore/Dummies/` | 14 safe default implementations |
| `ARES-Desktop/Sources/ARES/Providers/` | Concrete gateway providers (Ollama, Hermes) |
| `ARES-Desktop/Sources/ARES/Widgets/` | Composable UI widgets |
| `ARES-Desktop/Sources/ARES/Services/WiringBuilder.swift` | Builder pattern for backend selection |
| `ARES-Desktop/Sources/ARES/Views/DashboardView.swift` | Main dashboard with layout config |

---

## Building & Running

```bash
# Prerequisites: Swift 6.1+, macOS 14+

cd ~/GitHub/ARES
swift build          # 0 errors, clean compile
swift test           # 9/9 tests passing
swift run ARES       # Launch the app
```

### Environment Configuration

Set `ARES_ENV` to select development or production mode:

```bash
# Development mode (all dummies, no external services needed)
ARES_ENV=development swift run ARES

# Production mode (rejects dummies, requires real backends)
ARES_ENV=production HERMES_URL=http://localhost:8642 swift run ARES
```

### Gateway Setup (Optional)

For Hermes backend:

```bash
# Enable the api_server platform in Hermes config
hermes config set gateway.platforms.api_server.enabled true
hermes config set gateway.platforms.api_server.key YOUR_API_KEY

# Or add to ~/.hermes/.env:
echo "API_SERVER_KEY=your_api_key_here" >> ~/.hermes/.env

# Restart the gateway
hermes gateway restart
```

The app auto-detects the API key from `~/.hermes/.env` (`API_SERVER_KEY`).

For Ollama backend:

```bash
# Install Ollama from ollama.ai
# Pull a model
ollama pull gemma2:7b
ollama pull qwen2-vl:7b

# Ollama listens on localhost:11434 by default
```

The ModelPickerWidget shows all available Ollama models and allows runtime switching.

---

## How to Extend

### Add a New Gateway Provider

```swift
// 1. Conform to GatewayProvider protocol
final class CustomGatewayProvider: GatewayProvider {
    var identifier: String { "custom" }
    var serviceName: String { "Custom Backend" }
    var capabilities: Set<String> { ["reasoning", "streaming"] }
    
    func prompt(_ message: String, context: ConversationContext, options: GatewayOptions) async throws -> GatewayResponse { ... }
    func promptStream(_ message: String, context: ConversationContext, options: GatewayOptions) -> AsyncStream<StreamedToken> { ... }
    func executeToolCall(_ call: ToolCall, context: ConversationContext) async throws -> ToolResult { ... }
    func healthCheck() async throws -> GatewayHealth { ... }
    func getConfig() async throws -> GatewayConfig { ... }
}

// 2. Switch at runtime
let gateway = CustomGatewayProvider()
CompanionChatService.shared.switchProvider(gateway)
```

### Add a New Widget

```swift
// 1. Create widget (no imports of other widgets)
struct CustomWidget: View {
    var body: some View {
        VStack { /* custom UI */ }
    }
}

// 2. Add to DashboardLayout
enum WidgetType {
    case custom
}

// 3. Render in DashboardView
case .custom:
    CustomWidget()
```

---

## Status

**Phase 1: Complete ✅**
- 14 protocol contracts defined
- 14 dummy implementations (safe defaults)
- Wiring builder with production safety checks
- Build clean, tests pass

**Phase 2: Complete ✅**
- OllamaGatewayProvider + HermesGatewayProvider (swappable at runtime)
- CompanionChatService refactored to use any GatewayProvider
- 5 modular widgets (Chat, Avatar, History, ModelPicker, Perception)
- Dashboard with persistent layout configuration
- Build clean (0.31s), 9/9 tests passing

---

## Tech Stack

| Component | Choice |
|-----------|--------|
| Language | Swift 6.1, SwiftUI |
| LLM Backend | Pluggable (Ollama, Hermes, custom via protocol) |
| Streaming | SSE over HTTP (OpenAI-compatible) |
| Local Models | Ollama (localhost:11434) |
| Agent Backend | Hermes (localhost:8642, optional) |
| macOS Target | 14.0+ |
| iOS Target | 17.0+ |
| Architecture | ARESCore (library) + ARES (app) |
| Concurrency | Swift Concurrency (async/await, Sendable) |
| UI Framework | SwiftUI with composable widgets |
| Persistence | JSON (layout config), TOML/JSONL (memory) |

---

## License

Private repo. All rights reserved.