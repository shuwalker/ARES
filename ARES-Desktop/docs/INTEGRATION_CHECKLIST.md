# ARES Modular Integration — Implementation Checklist

**Goal:** Wire protocol backends into the existing ARES-Desktop app with zero logic changes.

**Estimated Time:** 1 week of careful integration.

---

## Phase 1: Update ARESAppState (1 day)

The single source of truth for the app is `ARESAppState.swift`. We need to inject protocols here.

### 1.1 Add Protocol Properties

**File:** `ARES-Desktop/Sources/ARES/App/ARESAppState.swift`

Find the `@MainActor class ARESAppState` and add:

```swift
@MainActor
class ARESAppState: ObservableObject {
    // Existing properties...
    
    // NEW: Backend protocols (injected at startup)
    var embodiment: Embodiment
    var perceiver: Perceiver
    var memory: MemoryStore
    var voice: VoiceEngine
    var brain: ReasoningBrain
    
    init(
        embodiment: Embodiment = DummyEmbodiment(),
        perceiver: Perceiver = DummyPerceiver(),
        memory: MemoryStore = DummyMemoryStore(),
        voice: VoiceEngine = DummyVoiceEngine(),
        brain: ReasoningBrain = DummyReasoningBrain(),
        // ... existing init params
    ) {
        self.embodiment = embodiment
        self.perceiver = perceiver
        self.memory = memory
        self.voice = voice
        self.brain = brain
        // ... existing init body
    }
}
```

### 1.2 Add Convenience Initializer

```swift
extension ARESAppState {
    /// Convenience initializer that resolves backends from environment
    convenience init(environment: RuntimeEnvironment = .development) {
        let backends = resolveBackends(environment)
        self.init(
            embodiment: backends.embodiment,
            perceiver: backends.perceiver,
            memory: backends.memory,
            voice: backends.voice,
            brain: backends.brain
            // ... pass other existing params
        )
    }
}
```

### 1.3 Update ARESApp

**File:** `ARES-Desktop/Sources/ARES/App/ARESApp.swift`

```swift
@main
struct ARESApp: App {
    @State private var appState: ARESAppState
    
    init() {
        // Detect environment from launch args or env vars
        let env = environmentFromLaunchArgs()
        _appState = State(initialValue: ARESAppState(environment: env))
    }
    
    var body: some Scene {
        WindowGroup {
            ARESRootView()
                .environmentObject(appState)
                .environment(\.embodiment, appState.embodiment)
                .environment(\.perceiver, appState.perceiver)
                .environment(\.memory, appState.memory)
                .environment(\.voice, appState.voice)
                .environment(\.brain, appState.brain)
        }
    }
}
```

**Verification:**
```bash
swift build -c debug
# Should compile without errors
```

---

## Phase 2: Update Existing Views (3 days)

Update views that currently use services to use protocols instead.

### 2.1 CompanionView (Chat)

**File:** `ARES-Desktop/Sources/ARES/Views/Companion/CompanionView.swift`

**Before:**
```swift
struct CompanionView: View {
    @EnvironmentObject var appState: ARESAppState
    @State var hermesGateway: HermesGatewayService  // <-- concrete service
    
    var body: some View {
        // Uses hermesGateway.chat(message) or similar
    }
}
```

**After:**
```swift
struct CompanionView: View {
    @EnvironmentObject var appState: ARESAppState
    @Environment(\.brain) var brain: ReasoningBrain?
    
    var body: some View {
        // Uses brain?.respond(to: message) instead
    }
}
```

**Update conversation logic:**
```swift
func sendMessage(_ text: String) async {
    guard let brain = brain else { return }
    
    do {
        let response = try await brain.respond(
            to: text,
            context: ConversationContext(
                messages: conversationHistory,
                userInfo: ["user": appState.currentUser?.name ?? "Unknown"],
                tone: "casual"
            )
        )
        // Add response to conversation
        addMessage(role: .assistant, content: response)
    } catch {
        print("Brain error: \(error)")
    }
}
```

### 2.2 AvatarView (New)

**File:** `ARES-Desktop/Sources/ARES/Views/Avatar/AvatarView.swift`

This view doesn't exist yet. Create it to render the avatar and wire perception + embodiment:

```swift
struct AvatarView: View {
    @Environment(\.embodiment) var embodiment: Embodiment?
    @Environment(\.perceiver) var perceiver: Perceiver?
    
    @State var currentExpression = FaceExpression(emotion: "neutral")
    @State var currentFrame: CGImage?
    
    var body: some View {
        ZStack {
            // Background: live camera feed
            if let frame = currentFrame {
                Image(cgImage: frame)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea()
            }
            
            // Foreground: avatar sprite (placeholder)
            VStack {
                Circle()
                    .fill(Color.yellow.opacity(0.7))
                    .frame(width: 200, height: 200)
                    .overlay(
                        Text(currentExpression.emotion)
                            .font(.caption)
                    )
            }
        }
        .onAppear {
            startPerceptionLoop()
        }
    }
    
    private func startPerceptionLoop() {
        Task {
            // Landmarks stream
            if let perceiver = perceiver {
                for await landmarks in perceiver.landmarkStream {
                    await updateExpressionFromLandmarks(landmarks)
                }
            }
            
            // Frame stream
            if let perceiver = perceiver {
                while true {
                    if let frame = try? await perceiver.captureFrame() {
                        await MainActor.run {
                            currentFrame = frame
                        }
                    }
                    try? await Task.sleep(nanoseconds: 33_000_000)  // 30 fps
                }
            }
        }
    }
    
    @MainActor
    private func updateExpressionFromLandmarks(_ landmarks: FaceLandmarks) {
        // Determine emotion from landmarks
        if landmarks.headPitch > 0.1 {
            currentExpression = FaceExpression(emotion: "happy", intensity: 0.8)
        } else if landmarks.headYaw > 0.2 {
            currentExpression = FaceExpression(emotion: "thinking", intensity: 0.6)
        } else {
            currentExpression = FaceExpression(emotion: "neutral", intensity: 0.5)
        }
        
        Task {
            try? await embodiment?.setFaceExpression(currentExpression)
        }
    }
}
```

**Add to ARESRootView:**
```swift
struct ARESRootView: View {
    var body: some View {
        TabView {
            AvatarView()
                .tabItem {
                    Label("Avatar", systemImage: "sparkles")
                }
            
            CompanionView()
                .tabItem {
                    Label("Chat", systemImage: "message")
                }
            
            // ... other tabs
        }
    }
}
```

### 2.3 MemoryView (New)

**File:** `ARES-Desktop/Sources/ARES/Views/Memory/MemoryView.swift`

```swift
struct MemoryView: View {
    @Environment(\.memory) var memory: MemoryStore?
    @State var searchQuery = ""
    @State var memories: [Memory] = []
    
    var body: some View {
        VStack {
            TextField("Search memories", text: $searchQuery)
                .onChange(of: searchQuery) { _, newQuery in
                    Task { await searchMemories(newQuery) }
                }
            
            List(memories, id: \.id) { mem in
                VStack(alignment: .leading) {
                    Text(mem.content)
                        .font(.body)
                    Text(mem.timestamp.formatted())
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
        }
    }
    
    private func searchMemories(_ query: String) async {
        guard !query.isEmpty else {
            memories = []
            return
        }
        
        do {
            memories = try await memory?.retrieve(query: query, limit: 10) ?? []
        } catch {
            print("Memory search error: \(error)")
        }
    }
}
```

### 2.4 Settings

**File:** `ARES-Desktop/Sources/ARES/Views/Settings/SettingsView.swift`

Add a debug section:

```swift
struct SettingsView: View {
    @EnvironmentObject var appState: ARESAppState
    @Environment(\.embodiment) var embodiment: Embodiment?
    @Environment(\.perceiver) var perceiver: Perceiver?
    @Environment(\.memory) var memory: MemoryStore?
    @Environment(\.voice) var voice: VoiceEngine?
    @Environment(\.brain) var brain: ReasoningBrain?
    
    var body: some View {
        Form {
            Section("Backends") {
                LabeledContent("Embodiment", value: embodiment?.kind ?? "none")
                LabeledContent("Perceiver", value: perceiver?.isListening.description ?? "none")
                LabeledContent("Memory", value: memory?.capabilities.description ?? "none")
                LabeledContent("Voice", value: voice?.capabilities.description ?? "none")
                LabeledContent("Brain", value: brain?.capabilities.description ?? "none")
            }
            
            // ... existing settings
        }
    }
}
```

---

## Phase 3: Test Integration (2 days)

### 3.1 Unit Tests for Wiring

**File:** `ARES-Desktop/Tests/ARESTests/WiringTests.swift`

```swift
import XCTest
@testable import ARES

final class WiringTests: XCTestCase {
    func testResolveBackendsDevelopment() {
        let stack = resolveBackends(.development)
        XCTAssertNotNil(stack.embodiment)
        XCTAssertNotNil(stack.perceiver)
        XCTAssertNotNil(stack.memory)
        XCTAssertNotNil(stack.voice)
        XCTAssertNotNil(stack.brain)
    }
    
    func testDummyEmbodiment() async throws {
        let embodiment = DummyEmbodiment()
        try await embodiment.setFaceExpression(FaceExpression(emotion: "happy"))
        // If no error, implementation works
    }
    
    func testDummyPerceiver() async throws {
        let perceiver = DummyPerceiver()
        try await perceiver.startListening()
        let isListening = await perceiver.isListening
        XCTAssertTrue(isListening)
    }
}
```

### 3.2 Integration Test

**File:** `ARES-Desktop/Tests/ARESTests/AppStateIntegrationTests.swift`

```swift
@MainActor
final class AppStateIntegrationTests: XCTestCase {
    func testAppStateInitializesWithBackends() {
        let appState = ARESAppState(environment: .testing)
        XCTAssertNotNil(appState.embodiment)
        XCTAssertNotNil(appState.perceiver)
        XCTAssertNotNil(appState.memory)
    }
    
    func testConversationFlow() async throws {
        let appState = ARESAppState(environment: .testing)
        
        let response = try await appState.brain.respond(
            to: "Hello",
            context: ConversationContext()
        )
        XCTAssertFalse(response.isEmpty)
    }
}
```

### 3.3 Manual Testing

**Checklist:**
- [ ] App launches with `ARES_ENV=development`
- [ ] Avatar tab shows placeholder face
- [ ] Chat tab shows input field
- [ ] Console shows emoji debug messages
- [ ] Settings tab shows backend capabilities
- [ ] No crashes or missing protocol implementations

---

## Phase 4: Documentation (1 day)

### 4.1 Add Comments

```swift
// In each view that uses protocols:

struct CompanionView: View {
    // MARK: - Backends (injected via SwiftUI environment)
    // These are protocols defined in ARESCore/Contracts
    // Concrete implementations selected in Wiring.swift
    
    @Environment(\.brain) var brain: ReasoningBrain?
    @Environment(\.memory) var memory: MemoryStore?
    
    // Implementation uses brain.respond() and memory.store()
    // Zero coupling to concrete classes
}
```

### 4.2 Update README

Add to `ARES-Desktop/README.md`:

```markdown
## Architecture

ARES uses a modular, protocol-based architecture inspired by Lilith-AI, JROS, and AIAvatarKit.

### Layers

1. **ARESCore** — Protocol definitions + shared models
2. **Views** — SwiftUI, uses only protocols
3. **Wiring.swift** — Backend selection at startup
4. **Sidecars** — Python services (perception, avatar, voice, memory, brain)

### Adding a Backend

See [MODULAR_INTEGRATION_GUIDE.md](../MODULAR_INTEGRATION_GUIDE.md).

## Running

```bash
# Development (dummies)
swift run ARES

# Production (real backends)
docker-compose up -d && ARES_ENV=production swift run ARES

# Testing
swift test
```
```

---

## Phase 5: Cleanup (1 day)

### 5.1 Archive Old Services

Move old concrete service implementations that are now replaced:

```bash
mkdir -p ARES-Desktop/.ares/_archive
mv Sources/ARES/Services/HermesGatewayService.swift .ares/_archive/
# Keep for reference, but don't import from active code
```

### 5.2 Remove Unused Imports

Search for and remove:
```swift
import HermesSDK  // No longer needed
@StateObject var hermesGateway: HermesGatewayService  // Replace with protocol
```

### 5.3 Build and Test

```bash
swift build -c release
swift test
```

**Expected:** All tests pass, no warnings, app launches.

---

## Summary

| Phase | Task | Days |
|-------|------|------|
| 1 | Update ARESAppState + Wiring integration | 1 |
| 2 | Update views (Companion, Avatar, Memory, Settings) | 3 |
| 3 | Unit + integration tests | 2 |
| 4 | Documentation + comments | 1 |
| 5 | Cleanup + final build | 1 |
| **Total** | | **8 days** |

After this, the app is fully modular. All backends are swappable. No views import concrete classes.

---

## Rollback Plan

If anything breaks:

1. Git has full history; revert commits
2. Old services in `.ares/_archive/` for reference
3. Dummies are no-ops; worst case, app prints emoji and continues

---

## Questions?

- **Does this break existing features?** No. Dummies preserve behavior; real backends are added incrementally.
- **Can I use the old HermesGatewayService?** Yes, but wire it via the brain protocol, not directly.
- **What if a protocol method fails?** Errors propagate; views handle them. Use try/catch around `await` calls.
- **How do I debug?** Enable console logging in Wiring.swift. Dummies print emoji messages.

---

## Next Steps

1. Pick a quiet moment to integrate Phase 1 (ARESAppState)
2. Compile and verify
3. Integrate Phase 2 (views) one at a time
4. Run tests after each view
5. Celebrate! 🎉
