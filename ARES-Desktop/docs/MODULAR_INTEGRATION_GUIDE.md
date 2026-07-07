# ARES Modular Integration Guide

**Status:** Architecture defined, Dummy implementations complete, Ready for real backends

**Date:** 2026-06-07

---

## What's Built (Today)

✅ **ARESCore** — Five protocols + five dummy implementations
- `Embodiment.swift` — Avatar, gaze, speech, approval
- `Perceiver.swift` — Face landmarks, prosody, audio
- `MemoryStore.swift` — Episodic and semantic memory
- `VoiceEngine.swift` — TTS, STT
- `ReasoningBrain.swift` — Planning, responding, reflection

✅ **Dummy Layer** — No-op implementations for rapid iteration
- `DummyEmbodiment.swift` — Prints to console
- `DummyPerceiver.swift` — Generates synthetic landmarks
- `DummyMemoryStore.swift` — In-memory dict
- `DummyVoiceEngine.swift` — Silent audio buffers
- `DummyReasoningBrain.swift` — Echoes input

✅ **Wiring Layer** — Backend selection at startup
- `Wiring.swift` — `resolveBackends()` function + environment detection
- `EnvironmentValues` extensions for SwiftUI injection

---

## Build Order (Next 8 Weeks)

### Week 1: Verify Protocol + Dummy Integration

**Goal:** Make sure the architecture compiles and Dummy backends work in the app.

```bash
cd ARES-Desktop
swift build -c debug

# Run app with dummies
ARES_ENV=development swift run ARES
```

**Checklist:**
- [ ] ARESCore module compiles
- [ ] ARESApp initializes with DummyEmbodiment, DummyPerceiver, etc.
- [ ] Console logs show emoji messages from dummies
- [ ] No circular imports or Sendable violations

### Week 2: Perception Sidecar (face landmarks)

**Goal:** Stream MediaPipe face landmarks over WebSocket.

**Backend** (`scripts/perception-svc/`):
```python
# perception-svc/main.py
import mediapipe as mp
import websockets
import json
import cv2
import numpy as np

class PerceptionService:
    def __init__(self, port=9201):
        self.port = port
        self.mp_face_mesh = mp.solutions.face_mesh
        self.face_mesh = self.mp_face_mesh.FaceMesh(
            max_num_faces=1,
            min_detection_confidence=0.5
        )
        self.cap = cv2.VideoCapture(0)
    
    async def process_frame(self):
        ret, frame = self.cap.read()
        if not ret:
            return None
        
        results = self.face_mesh.process(cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
        
        if results.multi_face_landmarks:
            landmarks = results.multi_face_landmarks[0]
            points = [
                {"x": lm.x * 512, "y": lm.y * 512}
                for lm in landmarks.landmark
            ]
            return {
                "timestamp": datetime.now().isoformat(),
                "points": points,
                "confidence": [0.95] * 468,
                "headRoll": 0, "headPitch": 0, "headYaw": 0
            }
        return None

    async def handle_connection(self, websocket, path):
        while True:
            frame = await self.process_frame()
            if frame:
                await websocket.send(json.dumps(frame))
            await asyncio.sleep(1/30)  # 30 fps

async def main():
    async with websockets.serve(
        PerceptionService().handle_connection,
        "localhost",
        9201
    ):
        await asyncio.Future()  # run forever

if __name__ == "__main__":
    asyncio.run(main())
```

**Frontend** (`ARESPerceive/PerceptionClient.swift`):
```swift
class PerceptionClient: Perceiver {
    private var ws: URLSessionWebSocketTask?
    private let url: URL
    
    init(url: URL = URL(string: "ws://localhost:9201")!) {
        self.url = url
    }
    
    var landmarkStream: AsyncStream<FaceLandmarks> {
        AsyncStream { continuation in
            Task {
                do {
                    let session = URLSession(configuration: .default)
                    ws = session.webSocketTask(with: url)
                    ws?.resume()
                    
                    while true {
                        let message = try await ws!.receive()
                        if case .data(let data) = message {
                            let landmarks = try JSONDecoder().decode(
                                FaceLandmarks.self,
                                from: data
                            )
                            continuation.yield(landmarks)
                        }
                    }
                } catch {
                    print("PerceptionClient error: \(error)")
                    continuation.finish()
                }
            }
        }
    }
}
```

**Integration:**
```swift
// In Wiring.swift, production case:
perceiver: PerceptionClient(url: URL(string: "ws://localhost:9201")!),
```

**Verification:**
```swift
// In a test or debug view:
.onAppear {
    Task {
        for await landmarks in perceiver.landmarkStream {
            print("Got \(landmarks.points.count) landmarks")
        }
    }
}
```

**Status check:**
- [ ] perception-svc runs on port 9201
- [ ] Streams 30fps landmarks from webcam
- [ ] PerceptionClient receives and decodes them
- [ ] App shows live camera feed + skeleton overlay

### Week 3: Avatar Rendering (2D sprite morph)

**Goal:** Drive avatar expression from face landmarks.

**Create** `ARESBody/AvatarView.swift`:
```swift
struct AvatarView: View {
    @Environment(\.embodiment) var embodiment
    @Environment(\.perceiver) var perceiver
    @State var currentExpression = FaceExpression(emotion: "neutral")
    
    var body: some View {
        ZStack {
            // Placeholder: simple circle face
            Circle()
                .fill(Color.yellow)
                .frame(width: 200, height: 200)
            
            // Eyes
            HStack(spacing: 60) {
                Circle().fill(Color.black).frame(width: 30)
                Circle().fill(Color.black).frame(width: 30)
            }
            
            // Mouth (changes with expression)
            VStack {
                Spacer()
                switch currentExpression.emotion {
                case "happy":
                    Path { path in
                        path.addArc(center: .init(x: 100, y: 150), radius: 20, startAngle: .zero, endAngle: .pi, clockwise: false)
                    }
                    .stroke(Color.black, lineWidth: 2)
                case "sad":
                    Path { path in
                        path.addArc(center: .init(x: 100, y: 150), radius: 20, startAngle: .pi, endAngle: .zero, clockwise: false)
                    }
                    .stroke(Color.black, lineWidth: 2)
                default:
                    Path { path in
                        path.move(to: .init(x: 80, y: 150))
                        path.addLine(to: .init(x: 120, y: 150))
                    }
                    .stroke(Color.black, lineWidth: 2)
                }
                Spacer()
            }
        }
        .onAppear {
            Task {
                for await landmarks in perceiver?.landmarkStream ?? AsyncStream { _ in } {
                    // Extract emotion from landmarks
                    // For now, just cycle through emotions
                    await setExpression(landmarks)
                }
            }
        }
    }
    
    @MainActor
    func setExpression(_ landmarks: FaceLandmarks) {
        // Placeholder: determine emotion from head rotation
        if landmarks.headPitch > 0.1 {
            currentExpression = FaceExpression(emotion: "happy")
        } else if landmarks.headPitch < -0.1 {
            currentExpression = FaceExpression(emotion: "sad")
        } else {
            currentExpression = FaceExpression(emotion: "neutral")
        }
        
        Task {
            try? await embodiment?.setFaceExpression(currentExpression)
        }
    }
}
```

**Integration into main view:**
```swift
struct ARESRootView: View {
    var body: some View {
        ZStack {
            AvatarView()
            // ... other views
        }
    }
}
```

**Status check:**
- [ ] Avatar appears in app
- [ ] Expression changes with landmarks
- [ ] `setFaceExpression` is called on embodiment

### Week 4: Voice Sidecar (TTS)

**Goal:** Synthesize speech from text.

**Backend** (`scripts/voice-svc/`):
```python
# voice-svc/main.py
from kokoro import KokoroTTS
import numpy as np
from fastapi import FastAPI, WebSocket
import json
import io

app = FastAPI()
tts = KokoroTTS()

@app.post("/synthesize")
async def synthesize(request: dict):
    text = request["text"]
    prosody = request.get("prosody", {})
    
    # Synthesize with Kokoro
    audio = tts.synthesize(text, speed=prosody.get("rate", 1.0))
    
    # Return as base64 or raw bytes
    return {
        "sampleRate": 44100,
        "channels": 1,
        "samples": audio.tolist()
    }
```

**Frontend** (`ARESVoice/VoiceClient.swift`):
```swift
class VoiceClient: VoiceEngine {
    var capabilities: Set<String> { ["TTS", "STT"] }
    
    func synthesize(text: String, prosody: Prosody) async throws -> AudioBuffer {
        var request = URLRequest(url: URL(string: "http://localhost:9202/synthesize")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let payload: [String: Any] = [
            "text": text,
            "prosody": ["rate": prosody.rate, "pitch": prosody.pitch]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(AudioBuffer.self, from: data)
        return response
    }
}
```

**Status check:**
- [ ] voice-svc runs on port 9202
- [ ] VoiceClient synthesizes text
- [ ] App can play audio

### Weeks 5–6: Memory Sidecar (SQLite + embeddings)

**Backend** (`scripts/memory-svc/`):
```python
# memory-svc/main.py
import sqlite3
from sentence_transformers import SentenceTransformer
from fastapi import FastAPI
from pydantic import BaseModel
import json

app = FastAPI()
model = SentenceTransformer("all-MiniLM-L6-v2")
db = sqlite3.connect("ares_memory.db")

@app.post("/store")
async def store(memory: dict):
    content = memory["content"]
    embedding = model.encode(content).tolist()
    
    db.execute(
        "INSERT INTO memories (id, content, embedding) VALUES (?, ?, ?)",
        (memory.get("id"), content, json.dumps(embedding))
    )
    db.commit()
    return {"id": memory.get("id")}

@app.post("/retrieve")
async def retrieve(query: dict):
    q = query["query"]
    q_embedding = model.encode(q)
    
    # Cosine similarity search
    results = db.execute("SELECT id, content FROM memories").fetchall()
    # Score and sort
    return {"memories": results[:query.get("limit", 10)]}
```

**Frontend** (`ARESMemory/MemoryClient.swift`):
```swift
class MemoryClient: MemoryStore {
    var capabilities: Set<String> { ["vectorSearch", "persistence"] }
    
    func store(_ memory: Memory) async throws -> String {
        var request = URLRequest(url: URL(string: "http://localhost:9203/store")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(memory)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(["id": String].self, from: data)
        return response["id"] ?? ""
    }
}
```

**Status check:**
- [ ] memory-svc runs on port 9203
- [ ] Stores memories to SQLite
- [ ] Retrieves by semantic search

### Weeks 7–8: Brain Sidecar (Hermes integration)

**Goal:** Wire reasoning loop to Hermes Agent.

**Backend** (`scripts/brain-svc/`):
```python
# brain-svc/main.py
from fastapi import FastAPI
import subprocess
import json

app = FastAPI()

@app.post("/respond")
async def respond(request: dict):
    user_input = request["input"]
    
    # Call Hermes Agent via MCP or CLI
    result = subprocess.run(
        ["hermes", "--query", user_input],
        capture_output=True,
        text=True
    )
    
    return {"response": result.stdout}
```

**Frontend** (`ARESBrain/BrainClient.swift`):
```swift
class BrainClient: ReasoningBrain {
    var capabilities: Set<String> { ["respond", "tools", "memory"] }
    
    func respond(to input: String, context: ConversationContext) async throws -> String {
        var request = URLRequest(url: URL(string: "http://localhost:9204/respond")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(["input": input])
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(["response": String].self, from: data)
        return response["response"] ?? ""
    }
}
```

**Status check:**
- [ ] brain-svc runs on port 9204
- [ ] Responds to queries via Hermes
- [ ] Returns coherent answers

---

## Adding a New Backend (Template)

To add a backend for any layer (e.g., a new TTS engine):

### 1. Implement the Protocol

**File:** `ARESCore/Contracts/VoiceEngine.swift` (already exists)

```swift
public protocol VoiceEngine: AnyObject, Sendable {
    func synthesize(...) async throws -> AudioBuffer
    // ... etc
}
```

### 2. Create a Concrete Implementation

**File:** `ARESVoice/MyNewVoiceEngine.swift`

```swift
class MyNewVoiceEngine: VoiceEngine {
    var capabilities: Set<String> { ["TTS", "STT"] }
    
    func synthesize(text: String, prosody: Prosody) async throws -> AudioBuffer {
        // Your implementation here
    }
}
```

### 3. Register in Wiring

**File:** `ARES/Wiring.swift`

```swift
case .production:
    return BackendStack(
        // ...
        voice: MyNewVoiceEngine(),  // <-- one line
        // ...
    )
```

### 4. Done

Views and logic don't change. The app uses your new backend immediately.

---

## Testing Strategy

Each backend should have unit tests:

```swift
// Tests/ARESVoiceTests/MyNewVoiceEngineTests.swift
final class MyNewVoiceEngineTests: XCTestCase {
    func testSynthesize() async throws {
        let engine = MyNewVoiceEngine()
        let audio = try await engine.synthesize(
            text: "Hello",
            prosody: Prosody(energy: 0.8)
        )
        XCTAssertEqual(audio.sampleRate, 44100)
    }
}
```

---

## Docker Compose for All Sidecars

Create `docker-compose.yml` at repo root:

```yaml
version: '3.8'

services:
  perception-svc:
    build: ./scripts/perception-svc
    ports:
      - "9201:9201"
    environment:
      - CAMERA_ID=0

  avatar-svc:
    build: ./scripts/avatar-svc
    ports:
      - "9202:9202"

  voice-svc:
    build: ./scripts/voice-svc
    ports:
      - "9202:9202"

  memory-svc:
    build: ./scripts/memory-svc
    ports:
      - "9203:9203"
    volumes:
      - ./data:/data

  brain-svc:
    build: ./scripts/brain-svc
    ports:
      - "9204:9204"
    environment:
      - HERMES_MCP_URL=http://localhost:5678

networks:
  default:
    name: ares-network
```

**Start all sidecars:**
```bash
docker-compose up -d
ARES_ENV=production swift run ARES
```

---

## Summary

**Today:** Protocol definitions + dummies complete. App compiles and logs emoji messages.

**Week 1–8:** Build real backends one by one. Each one is tested independently, then integrated via Wiring.swift with one line.

**Week 8+:** Swap backends. Implement robot embodiment without touching the app. Switch TTS engines. Add new perception sources. None of it touches the app.

---

## Files to Keep Updated

1. `docs/MODULAR_ARCHITECTURE.md` — Design document (reference for patterns)
2. `ARES-Desktop/MODULAR_INTEGRATION_GUIDE.md` — This document (build roadmap)
3. `ARES-Desktop/Sources/ARES/Wiring.swift` — Swappable backend selection
4. `ARESCore/Contracts/*.swift` — Protocol definitions
5. `ARESCore/Dummies/*.swift` — Test implementations

**Rule:** Never add new protocols without a dummy. Never add a production backend without a test. Never import concrete implementations outside their module.
