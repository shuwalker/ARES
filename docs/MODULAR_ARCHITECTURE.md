# ARES Modular Architecture — Patterns from Lilith, JROS, AIAvatarKit

Date: 2026-06-07
Synthesized from: Lilith-AI, JROS, AIAvatarKit
Goal: Swap embodiment, perception, and reasoning backends without app changes

---

## Core Principles

1. **Protocols over Implementations** — Define contracts in ARESCore; implementations are swappable
2. **Capability Sets** — Declare what a backend *can* do; gate features at boot, not runtime
3. **Dependency Injection** — Caller chooses the backend; provide sensible defaults
4. **Layer Isolation** — Core imports only protocols; never concrete classes
5. **Stubs First** — Ship empty implementations (Dummy); populate later without breaking imports

---

## Architecture: Five Swappable Layers

```
┌─────────────────────────────────────────────────────────┐
│ ARESApp (Swift UI + Wiring)                             │
├─────────────────────────────────────────────────────────┤
│                     WIRING.swift                        │
│  (Selects which concrete impl per layer; 1-line swaps)  │
├──────┬──────────┬────────────┬───────────┬──────────────┤
│Body  │Perceive  │Memory      │Voice      │Brain         │
│      │          │            │           │              │
│ARESBody│ARESPerceive│ARESMemory│ARESVoice │ARESBrain    │
└──────┴──────────┴────────────┴───────────┴──────────────┘
         ↓
┌─────────────────────────────────────────────────────────┐
│ ARESCore (Protocols + Models)                           │
│                                                         │
│  Embodiment.Protocol                                    │
│  Perceiver.Protocol                                     │
│  MemoryStore.Protocol                                   │
│  VoiceEngine.Protocol                                   │
│  ReasoningBrain.Protocol                                │
│                                                         │
│  Models: FaceLandmark, Prosody, Message, etc.          │
└─────────────────────────────────────────────────────────┘
         ↓
┌─────────────────────────────────────────────────────────┐
│ Python Sidecars (Swappable Backends)                    │
│                                                         │
│  perception-svc                                         │
│    ├─ MediaPipe landmarks + pose                        │
│    └─ Fallback: OpenPose or manual keypoints            │
│                                                         │
│  avatar-svc                                             │
│    ├─ 3D model + animation (UE5/Unity streaming)        │
│    └─ Fallback: 2D sprite morph or CSS avatar           │
│                                                         │
│  voice-svc                                              │
│    ├─ Kokoro TTS + STT (local)                          │
│    └─ Fallback: system TTS/STT                          │
│                                                         │
│  memory-svc                                             │
│    ├─ SQLite + vector embeddings                        │
│    └─ Fallback: in-memory dict                          │
│                                                         │
│  brain-svc                                              │
│    ├─ Hermes Agent (prompt assembly + tool calls)       │
│    └─ Fallback: Claude API or local LLM                 │
│                                                         │
│  world-svc                                              │
│    ├─ Scene graph + object tracking                     │
│    └─ Fallback: stateless object list                   │
└─────────────────────────────────────────────────────────┘
```

---

## Layer 1: ARESCore Protocols

Located in `ARES-Desktop/Sources/ARESCore/Contracts/`

### Embodiment.swift
```swift
@runtime_checkable
protocol Embodiment: AnyObject {
    var state: EmbodimentState { get async }
    var capabilities: Set<String> { get }
    var kind: String { get }  // "desktop", "robot", "watch"
    
    func setFaceExpression(_ expr: FaceExpression) async throws
    func setEyeGaze(_ target: EyeGazeTarget) async throws
    func speak(text: String, prosody: Prosody) async throws
    func requestApproval(_ action: ApprovalRequest) async throws -> Bool
    
    func getCapabilityInfo(name: String) -> [String: AnyCodable]?
}

enum EmbodimentState: Codable {
    case idle, listening, thinking, speaking, sleeping
}

struct FaceExpression: Codable {
    let emotion: String  // "happy", "sad", "thinking", "confused", etc.
    let intensity: Double  // 0.0 ... 1.0
    let blinking: Bool
}

struct EyeGazeTarget: Codable {
    let point: CGPoint  // in screen coords or 3D space
    let duration: TimeInterval
}
```

### Perceiver.swift
```swift
protocol Perceiver: AnyObject {
    var landmarkStream: AsyncStream<FaceLandmarks> { get }
    var prosodyStream: AsyncStream<Prosody> { get }
    
    func captureFrame() async throws -> UIImage
    func startListening() async throws
    func stopListening() async throws
    var isListening: Bool { get }
}

struct FaceLandmarks: Codable {
    let timestamp: Date
    let points: [CGPoint]  // 468 MediaPipe points or 17 OpenPose points
    let confidence: [Double]
    let headRoll: Double
    let headPitch: Double
    let headYaw: Double
}

struct Prosody: Codable {
    let energy: Double
    let pitch: Double
    let rate: Double
    let timestamp: Date
}
```

### MemoryStore.swift
```swift
protocol MemoryStore: AnyObject {
    func store(_ memory: Memory) async throws
    func retrieve(query: String, limit: Int) async throws -> [Memory]
    func update(_ id: String, with updates: [String: AnyCodable]) async throws
    func delete(_ id: String) async throws
    
    var capabilities: Set<String> { get }  // e.g., {"vectorSearch", "persistence", "iCloud"}
}

struct Memory: Codable {
    let id: String
    let content: String
    let context: [String: AnyCodable]
    let timestamp: Date
    let embedding: [Double]?  // optional; if nil, backend computes it
}
```

### VoiceEngine.swift
```swift
protocol VoiceEngine: AnyObject {
    func synthesize(text: String, prosody: Prosody) async throws -> AudioBuffer
    func recognize(audio: AudioBuffer) async throws -> String
    var capabilities: Set<String> { get }  // e.g., {"TTS", "STT", "prosody"}
}

struct AudioBuffer: Codable {
    let sampleRate: Int
    let channels: Int
    let samples: [Float]
}
```

### ReasoningBrain.swift
```swift
protocol ReasoningBrain: AnyObject {
    func plan(context: WorldModel) async throws -> [Task]
    func respond(to input: String) async throws -> String
    func reflect(on experience: Experience) async throws
    
    var capabilities: Set<String> { get }  // e.g., {"tools", "memory", "streaming"}
}

struct Task: Codable {
    let id: String
    let description: String
    let requiredCapabilities: Set<String>
    let approvalRequired: Bool
}

struct WorldModel: Codable {
    let objects: [Object]
    let relationships: [(String, String, String)]  // (subject, relation, object)
    let timestamp: Date
}
```

---

## Layer 2: ARESCore Models

Located in `ARES-Desktop/Sources/ARESCore/Models/`

All models are Codable and conform to Sendable for concurrency.

```swift
// Message.swift
struct Message: Codable, Sendable {
    let id: String
    let role: Role  // .user, .assistant, .system
    let content: String
    let attachments: [Attachment]
    let timestamp: Date
    let metadata: [String: AnyCodable]
}

// Attachment.swift
enum Attachment: Codable, Sendable {
    case image(UIImage)
    case audio(AudioBuffer)
    case text(String)
    case structured([String: AnyCodable])
}

// ApprovalRequest.swift
struct ApprovalRequest: Codable {
    let action: String
    let impact: ApprovalImpact
    let requiredCapabilities: Set<String>
    let timeout: TimeInterval
    
    enum ApprovalImpact {
        case informational, confirmRequired, riskMitigation
    }
}
```

---

## Layer 3: Concrete Implementations (Python Sidecars)

Each sidecar is a typed client in Swift + Python backend.

### perception-svc

**Python backend** (`scripts/perception-svc/main.py`):
```python
from dataclasses import dataclass
from typing import Protocol
import mediapipe as mp

class PerceptionBackend(Protocol):
    async def process_frame(self, frame: np.ndarray) -> FaceLandmarks: ...

class MediaPipeBackend(PerceptionBackend):
    def __init__(self):
        self.mp_pose = mp.solutions.pose
        self.pose = self.mp_pose.Pose()
    
    async def process_frame(self, frame: np.ndarray) -> FaceLandmarks:
        results = self.pose.process(frame)
        # Convert MediaPipe landmarks to FaceLandmarks struct
        return FaceLandmarks(...)

class OpenPoseBackend(PerceptionBackend):
    # Fallback: OpenPose or manual keypoint detection
    pass

# WebSocket server exposes:
# - /subscribe/landmarks → AsyncStream<FaceLandmarks>
# - /frame → POST image, get landmarks
```

**Swift client** (`ARESPerceive/PerceptionClient.swift`):
```swift
class PerceptionClient: Perceiver {
    private let ws: URLSessionWebSocketTask
    var landmarkStream: AsyncStream<FaceLandmarks> {
        AsyncStream { continuation in
            Task {
                for await msg in ws.messages {
                    let landmarks = try JSONDecoder().decode(FaceLandmarks.self, from: msg.data)
                    continuation.yield(landmarks)
                }
            }
        }
    }
}
```

### avatar-svc

**Python backend** (`scripts/avatar-svc/main.py`):
```python
class AvatarBackend(Protocol):
    async def set_expression(self, expr: FaceExpression) -> None: ...
    async def set_gaze(self, target: EyeGazeTarget) -> None: ...

class Unreal5Backend(AvatarBackend):
    # Streams landmarks to UE5 WebSocket
    pass

class Sprite2DBackend(AvatarBackend):
    # Morphs 2D sprite based on expressions
    pass

# WebSocket server exposes:
# - /expression → POST FaceExpression
# - /gaze → POST EyeGazeTarget
# - /frame → GET current rendered frame (PNG)
```

### voice-svc

**Python backend** (`scripts/voice-svc/main.py`):
```python
class VoiceBackend(Protocol):
    async def synthesize(self, text: str, prosody: Prosody) -> AudioBuffer: ...
    async def recognize(self, audio: AudioBuffer) -> str: ...

class KokoroBackend(VoiceBackend):
    # TTS: Kokoro local model
    # STT: Whisper
    pass

class SystemTTSBackend(VoiceBackend):
    # Fallback: macOS TTS + STT
    pass

# WebSocket server exposes:
# - /synthesize → POST {text, prosody}, get audio stream
# - /recognize → POST audio, get text
```

### memory-svc

**Python backend** (`scripts/memory-svc/main.py`):
```python
class MemoryBackend(Protocol):
    async def store(self, memory: Memory) -> str: ...
    async def retrieve(self, query: str, limit: int) -> list[Memory]: ...

class SQLiteVectorBackend(MemoryBackend):
    # SQLite + sentence-transformers for embeddings
    def __init__(self):
        self.db = sqlite3.connect("ares_memory.db")
        self.model = SentenceTransformer("all-MiniLM-L6-v2")
    
    async def store(self, memory: Memory):
        embedding = self.model.encode(memory.content)
        self.db.execute("INSERT INTO memories (...) VALUES (...)", ...)

class InMemoryBackend(MemoryBackend):
    # Fallback: simple dict with no persistence
    pass

# HTTP server exposes:
# - POST /store → {content, context} → id
# - POST /retrieve → {query, limit} → [Memory]
```

### brain-svc

**Python backend** (`scripts/brain-svc/main.py`):
```python
class ReasoningBackend(Protocol):
    async def plan(self, context: WorldModel) -> list[Task]: ...
    async def respond(self, input: str) -> str: ...

class HermesBackend(ReasoningBackend):
    # Calls Hermes Agent for reasoning
    async def respond(self, input: str) -> str:
        # Assemble prompt with memory, world state
        # Call Hermes MCP or HTTP gateway
        # Stream/parse response
        pass

class ClaudeAPIBackend(ReasoningBackend):
    # Fallback: direct API call to Claude
    pass

# HTTP server exposes:
# - POST /respond → {input, context} → response (streaming)
# - POST /plan → {context} → [Task]
```

---

## Layer 4: Wiring (ARES-Desktop/Sources/ARES/Wiring.swift)

```swift
enum ResolvedBackends {
    case development
    case production
    case testing
}

func resolveBackends(_ mode: ResolvedBackends) -> (
    embodiment: Embodiment,
    perceiver: Perceiver,
    memory: MemoryStore,
    voice: VoiceEngine,
    brain: ReasoningBrain
) {
    switch mode {
    case .development:
        return (
            embodiment: DesktopEmbodiment(capabilities: [
                "expression", "gaze", "speech", "approval"
            ]),
            perceiver: PerceptionClient(url: "ws://localhost:9201"),
            memory: InMemoryMemoryStore(),  // Fast iteration
            voice: SystemVoiceEngine(),     // macOS TTS
            brain: DirectClaudeAPI()        // Fast feedback
        )
    
    case .production:
        return (
            embodiment: DesktopEmbodiment(capabilities: [
                "expression", "gaze", "speech", "approval"
            ]),
            perceiver: PerceptionClient(url: "ws://perception-svc:9201"),
            memory: SQLiteVectorMemoryStore(),
            voice: KokoroVoiceEngine(url: "ws://voice-svc:9202"),
            brain: HermesAgentBrain(url: "http://brain-svc:9203")
        )
    
    case .testing:
        return (
            embodiment: DummyEmbodiment(),
            perceiver: DummyPerceiver(),
            memory: InMemoryMemoryStore(),
            voice: DummyVoiceEngine(),
            brain: DummyBrain()
        )
    }
}

// Usage in ARESApp
@main
struct ARESApp: App {
    @State var backends = resolveBackends(.development)
    
    var body: some Scene {
        WindowGroup {
            ARESRootView()
                .environment(\.embodiment, backends.embodiment)
                .environment(\.perceiver, backends.perceiver)
                .environment(\.memory, backends.memory)
                .environment(\.voice, backends.voice)
                .environment(\.brain, backends.brain)
        }
    }
}
```

---

## Layer 5: Dummy Implementations (for testing and fast iteration)

Located in `ARES-Desktop/Sources/ARESCore/Dummies/`

```swift
// DummyEmbodiment.swift
class DummyEmbodiment: Embodiment {
    var state: EmbodimentState = .idle
    var capabilities: Set<String> { ["expression", "gaze", "speech"] }
    var kind: String { "dummy" }
    
    func setFaceExpression(_ expr: FaceExpression) async throws {
        print("🤖 [DUMMY] Setting expression: \(expr.emotion)")
    }
    
    func setEyeGaze(_ target: EyeGazeTarget) async throws {
        print("🤖 [DUMMY] Setting gaze to \(target.point)")
    }
    
    func speak(text: String, prosody: Prosody) async throws {
        print("🤖 [DUMMY] Speaking: \(text)")
    }
    
    // ... etc
}

// DummyPerceiver.swift
class DummyPerceiver: Perceiver {
    var landmarkStream: AsyncStream<FaceLandmarks> {
        AsyncStream { continuation in
            // Generate synthetic landmarks for testing
            while true {
                let synthetic = FaceLandmarks(...)
                continuation.yield(synthetic)
                try? await Task.sleep(nanoseconds: 33_000_000)  // 30 fps
            }
        }
    }
    
    // ... etc
}
```

---

## Integration Checklist

### Week 1: Define Contracts
- [ ] ARESCore: Write five Protocol files (Embodiment, Perceiver, MemoryStore, VoiceEngine, Brain)
- [ ] ARESCore: Write model files (Message, Attachment, ApprovalRequest, etc.)
- [ ] ARESCore: Add Dummy implementations for each protocol

### Week 2: Perception Sidecar
- [ ] perception-svc: MediaPipe backend
- [ ] ARESPerceive: WebSocket client to perception-svc
- [ ] Test: Can ARESApp show live camera + landmarks overlay

### Week 3: Avatar Sidecar
- [ ] avatar-svc: 2D sprite morph backend (minimum)
- [ ] ARESBody: Render landmarks on avatar
- [ ] Test: Facial expressions drive avatar changes

### Week 4: Voice Sidecar
- [ ] voice-svc: System TTS backend
- [ ] ARESVoice: Synthesize + recognize
- [ ] Test: App can say and listen

### Month 2: Memory + Brain
- [ ] memory-svc: SQLite backend
- [ ] brain-svc: Hermes gateway
- [ ] ARESBrain: Reasoning loop with memory

### Month 3+: Embodiment Swap
- [ ] Add robot embodiment (JROS bridge)
- [ ] Add watch embodiment
- [ ] Prove one backend swap (e.g., Kokoro TTS) without app changes

---

## Swappable Component Template

To add a new backend for any layer, follow this pattern:

**1. Define the interface in ARESCore** (if not already defined):
```swift
protocol MyNewLayer: AnyObject {
    // Contract goes here
}
```

**2. Implement a Dummy** in ARESCore/Dummies:
```swift
class DummyMyNewLayer: MyNewLayer {
    // No-op implementation
}
```

**3. Implement the production backend** (Python sidecar or Swift):
```swift
class RealMyNewLayer: MyNewLayer {
    // Real implementation
}
```

**4. Register in Wiring.swift**:
```swift
func resolveBackends(...) -> (..., myNewLayer: MyNewLayer, ...) {
    return (..., myNewLayer: RealMyNewLayer(), ...)
}
```

**5. Inject into the app**:
```swift
.environment(\.myNewLayer, backends.myNewLayer)
```

That's it. One protocol, one wiring line, zero changes to views or logic.

---

## References

- **Lilith-AI**: `embodiment/_interface.py` + `core/` isolation
- **JROS**: `embodiment/_interface.py` + capability gating
- **AIAvatarKit**: ABC + Dummy + concrete stacking pattern
